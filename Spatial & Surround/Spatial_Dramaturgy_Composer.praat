# ============================================================
# Praat AudioTools - Spatial_Dramaturgy_Composer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spatial Dramaturgy Composer — space as a carrier of musical form.
#   Category: Spatial & Surround. Pure Praat.
#
#     form composition  ->  spatial state  ->  trajectory realisation
#
#   1. A dramaturgical curve D(t) in 0..1 is DRAWN (an editable RealTier),
#      ANALYSED from the source (weighted, normalised descriptors), or taken
#      from one of 14 ARCHETYPES.
#   2. D(t) drives seven spatial dimensions — spread, distance, movement
#      rate, irregularity, elevation, peripheralisation, fragmentation —
#      each through its own mapping: min, max, direction (+ positive,
#      - inverted, = fixed), response curve (lin exp log sig thr step rnd)
#      and influence. Character (Subtle..Radical) scales how far every
#      dimension moves away from its state at D = 0. A climax can therefore
#      expand the field or collapse it (see the Frozen Climax strategy).
#   3. Trajectories are DERIVED from that state, never drawn: agents keep a
#      common azimuth when spread is low and separate as it grows; rotation
#      speed follows the movement rate; irregularity adds seeded smooth
#      random deviation; fragmentation lets agents rotate independently;
#      peripheralisation pushes occupancy from the front to the sides and
#      rear; elevation and distance shape the image as described below.
#
#   Spatial agents (fragmentation): the signal is PARTITIONED, never
#   duplicated at full level. Agent 1 carries the whole sound; as
#   fragmentation rises, agent j (j >= 2) is released and takes over its
#   share — a frequency band (default), a cyclic time slice, or a short
#   delayed copy (gain-normalised under a decorrelated-copy assumption) —
#   which agent 1 gives up. Bands and slices sum back to the original exactly.
#
#   Rendering — what is and is not simulated:
#   - Stereo / Quad / 8-ring / N-ring: speaker-based AMPLITUDE panning
#     (equal-power between neighbouring speakers; stereo uses the left-
#     right projection, so front and rear fold together).
#   - Ambisonic: first-order ENCODING, AmbiX convention (ACN W Y Z X, SN3D).
#     No decoder is included.
#   - Distance: amplitude attenuation (1/(1+2d): up to -9.5 dB) and a
#     direct/diffuse blend (diffuse = equal energy to all speakers; in
#     Ambisonics, reduced directional components). NO propagation delay,
#     air absorption or room model.
#   - Elevation: encoded in the Ambisonic output; on horizontal speaker
#     rings it cannot be reproduced and is rendered only as added
#     diffuseness (stated in the report).
#
#   Every curve in the figure is the data used for rendering. The final
#   channel panel is a routing-gain map by default; measured output energy
#   is available as an optional, slower diagnostic.
#
# Changelog v1.2:
#   - Rejects selection of more than one RealTier.
#   - Multichannel input is described correctly as averaged to mono.
#   - Analyze Source spectral-change bands are Nyquist-safe at low sample rates.
#   - Routing-gain visualisation weights each agent by release^2 (power), not
#     release (amplitude).
#   - Delayed-copy normalisation/reporting now states the decorrelation
#     assumption instead of claiming exact power normalisation.
#   - Figure/documentation wording updated to distinguish the default routing
#     map from the optional measured-output-energy diagnostic.
#
# Changelog v1.1:
#   - Direct/diffuse blend made energy-neutral. Direct and diffuse are the
#     same signal, so a g + b had power 1 + 2 a b sum(g), not 1: up to +3 dB
#     in stereo, and on rings rising elevation (rendered as diffuseness)
#     also got louder. Gains are now divided by sqrt(1 + 2 a b sum g).
#   - Delayed copies normalised by sqrt(1 + sum r^2) (was sum r).
#   - Analyze source: the smoothed curve is no longer stretched to 0..1 a
#     second time, so a nearly static source no longer produces a full
#     dramaturgical excursion; new Analysis sensitivity (scale around the
#     mean, 1 = as measured); the report gives the resulting D range.
#   - Agents released in mirrored pairs where possible (centre, +-1,
#     +-0.5, +-0.75); with an even agent count the final agent is unpaired.
#     Pairs spin and drift outward in mirror image; the side a single
#     centre source drifts to is chosen by the seed (was always right).
#   - Frequency bands from one forward FFT (copies of one Spectrum).
#   - Outputs: only the Sound (no Table; the RealTier is a temporary
#     carrier, removed once its values are in the control arrays).
#   - Energy panel: rendering-gain map by default; the measured version
#     (slower on many channels) is an option.
#
# Changelog v1.0:
#   - First release.
#
# Requires: Praat 6.3+. Nothing else.
# ============================================================

version$ = "1.2"

# ---- INPUT: one Sound, optionally with a RealTier as the drawn dramaturgy ----
nSnd = numberOfSelected("Sound")
nTier = numberOfSelected("RealTier")
if nSnd <> 1
    exitScript: "Select one Sound (optionally together with a RealTier holding a dramaturgy curve 0..1)."
endif
if nTier > 1
    exitScript: "Select at most one RealTier together with the Sound."
endif
srcObjOrig = selected("Sound")
srcName$ = selected$("Sound")
userTier = 0
if nTier = 1
    userTier = selected("RealTier")
endif

# ============================================================
# FORM
# ============================================================
form: "Spatial Dramaturgy Composer v1.2"
    optionmenu: "Dramaturgy", 3
        option: "Draw (edit a curve / use a selected RealTier)"
        option: "Analyze source"
        option: "Archetype"
    optionmenu: "Archetype", 3
        option: "Expansion"
        option: "Implosion"
        option: "Arch"
        option: "Inverted Arch"
        option: "Ascent"
        option: "Descent"
        option: "Encirclement"
        option: "Fragmentation"
        option: "Convergence"
        option: "Dissolution"
        option: "Accumulation"
        option: "Shock"
        option: "Waves"
        option: "Chaotic Escalation"
    optionmenu: "Spatial strategy", 1
        option: "Auto (from archetype)"
        option: "Intimate to Overwhelming"
        option: "Compression"
        option: "Explosion"
        option: "Breathing Space"
        option: "Orbiting Tension"
        option: "Fragmented Climax"
        option: "Frozen Climax"
        option: "Vertical Drama"
        option: "Peripheral Anxiety"
        option: "Dissolution"
        option: "Swarm"
        option: "Radical"
        option: "Custom mapping"
    optionmenu: "Character", 3
        option: "Subtle"
        option: "Moderate"
        option: "Dramatic"
        option: "Radical"
    optionmenu: "Output", 3
        option: "Stereo"
        option: "Quad (FL FR RL RR)"
        option: "8-channel ring"
        option: "Custom speaker ring"
        option: "Ambisonic FOA (AmbiX)"
    natural: "Max agents (1-8)", "4"
    integer: "Random seed", "30217"
    boolean: "Show details", 0
    boolean: "Draw visualisation", 1
    boolean: "Play result", 1
endform

maxAgents = max(1, min(8, max_agents))
seed = random_seed

# ============================================================
# DEFAULTS FOR THE DETAIL DIALOGS
# ============================================================
archStrength = 1.0
wInt = 1.0
wBright = 0.7
wChange = 0.8
wDensity = 0.6
wNoise = 0.4
wPitch = 0.0
smoothSec = 2.0
analysisSens = 1.0
measureEnergy = 0
fragMethod = 1
ringN = 12
maxSpeed = 120
normMode = 1

# ============================================================
# STRATEGIES (mapping presets): one text line per dimension
#   "min max dir curve influence"   dir: + inverted - fixed =
#   curves: lin exp log sig thr step rnd
# ============================================================
procedure strategy: .s
    # dimension order: spread, distance, rate, irregularity, elevation,
    # peripheral, fragmentation
    if .s = 2
        stratName$ = "Intimate to Overwhelming"
        map1$ = "0.05 0.95 + sig 1"
        map2$ = "0.05 0.5 + lin 1"
        map3$ = "0 0.7 + exp 1"
        map4$ = "0 0.6 + exp 1"
        map5$ = "0 0.3 + lin 0.5"
        map6$ = "0 0.9 + sig 1"
        map7$ = "0 1 + thr 1"
    elsif .s = 3
        stratName$ = "Compression"
        map1$ = "0.05 0.95 - lin 1"
        map2$ = "0.1 0.6 - lin 1"
        map3$ = "0 0.3 - lin 0.5"
        map4$ = "0 0.3 - lin 1"
        map5$ = "0 0 = lin 1"
        map6$ = "0 0.8 - lin 1"
        map7$ = "0 0.6 - lin 1"
    elsif .s = 4
        stratName$ = "Explosion"
        map1$ = "0.05 1 + thr 1"
        map2$ = "0.1 0.6 + thr 1"
        map3$ = "0 0.8 + thr 1"
        map4$ = "0 0.7 + thr 1"
        map5$ = "0 0.4 + thr 1"
        map6$ = "0 0.9 + thr 1"
        map7$ = "0 1 + thr 1"
    elsif .s = 5
        stratName$ = "Breathing Space"
        map1$ = "0.1 0.9 + sig 1"
        map2$ = "0.2 0.5 + lin 1"
        map3$ = "0.05 0.2 + lin 1"
        map4$ = "0 0.1 = lin 1"
        map5$ = "0 0.2 + lin 1"
        map6$ = "0 0.5 + lin 1"
        map7$ = "0 0.3 + lin 1"
    elsif .s = 6
        stratName$ = "Orbiting Tension"
        map1$ = "0.2 0.4 + lin 1"
        map2$ = "0.2 0.3 + lin 1"
        map3$ = "0.05 1 + exp 1"
        map4$ = "0 0.2 + lin 1"
        map5$ = "0 0 = lin 1"
        map6$ = "0.4 0.6 + lin 1"
        map7$ = "0 0.4 + thr 1"
    elsif .s = 7
        stratName$ = "Fragmented Climax"
        map1$ = "0.1 0.9 + sig 1"
        map2$ = "0.1 0.4 + lin 1"
        map3$ = "0.05 0.5 + lin 1"
        map4$ = "0 0.6 + exp 1"
        map5$ = "0 0.2 + lin 1"
        map6$ = "0 0.6 + lin 1"
        map7$ = "0 1 + exp 1"
    elsif .s = 8
        stratName$ = "Frozen Climax"
        map1$ = "0 0.8 - sig 1"
        map2$ = "0 0.6 - lin 1"
        map3$ = "0 0.6 - exp 1"
        map4$ = "0 0.5 - lin 1"
        map5$ = "0 0 = lin 1"
        map6$ = "0 0.7 - lin 1"
        map7$ = "0 0.7 - sig 1"
    elsif .s = 9
        stratName$ = "Vertical Drama"
        map1$ = "0.1 0.3 + lin 1"
        map2$ = "0.1 0.3 + lin 1"
        map3$ = "0 0.2 + lin 1"
        map4$ = "0 0.1 + lin 1"
        map5$ = "0 1 + sig 1"
        map6$ = "0 0.2 + lin 1"
        map7$ = "0 0.2 + lin 1"
    elsif .s = 10
        stratName$ = "Peripheral Anxiety"
        map1$ = "0.1 0.6 + lin 1"
        map2$ = "0.2 0.5 + lin 1"
        map3$ = "0.05 0.6 + lin 1"
        map4$ = "0 0.9 + exp 1"
        map5$ = "0 0.1 + lin 1"
        map6$ = "0 1 + exp 1"
        map7$ = "0 0.5 + thr 1"
    elsif .s = 11
        stratName$ = "Dissolution"
        map1$ = "0.1 1 + lin 1"
        map2$ = "0.05 1 + lin 1"
        map3$ = "0.05 0.3 - lin 1"
        map4$ = "0 0.6 + exp 1"
        map5$ = "0 0.3 + lin 1"
        map6$ = "0 0.7 + lin 1"
        map7$ = "0 0.6 + lin 1"
    elsif .s = 12
        stratName$ = "Swarm"
        map1$ = "0.2 1 + lin 1"
        map2$ = "0.2 0.4 + lin 1"
        map3$ = "0.1 0.8 + lin 1"
        map4$ = "0.1 0.9 + lin 1"
        map5$ = "0 0.3 + rnd 1"
        map6$ = "0.2 0.8 + lin 1"
        map7$ = "0 1 + lin 1"
    elsif .s = 13
        stratName$ = "Radical"
        map1$ = "0 1 + step 1"
        map2$ = "0 0.9 + thr 1"
        map3$ = "0 1 + exp 1"
        map4$ = "0 1 + rnd 1"
        map5$ = "0 0.8 + step 1"
        map6$ = "0 1 + thr 1"
        map7$ = "0 1 + step 1"
    elsif .s = 14
        stratName$ = "Encirclement"
        map1$ = "0.1 1 + step 1"
        map2$ = "0.1 0.3 + lin 1"
        map3$ = "0.05 0.3 + lin 1"
        map4$ = "0 0.15 + lin 1"
        map5$ = "0 0 = lin 1"
        map6$ = "0 1 + step 1"
        map7$ = "0 0.3 + lin 1"
    endif
endproc

# archetype -> matching strategy (used by "Auto")
procedure autoStrategy: .a
    .s = 2
    if .a = 5 or .a = 6
        .s = 9
    elsif .a = 7
        .s = 14
    elsif .a = 8 or .a = 9
        .s = 7
    elsif .a = 10
        .s = 11
    elsif .a = 11
        .s = 12
    elsif .a = 12
        .s = 4
    elsif .a = 13
        .s = 5
    elsif .a = 14
        .s = 13
    endif
endproc

# menu: 1 Auto, 2..13 strategies, 14 Custom. Internal strategy 14 is
# Encirclement, reachable only through Auto (archetype Encirclement).
if spatial_strategy = 1
    stratIdx = 2
    if dramaturgy = 3
        @autoStrategy: archetype
        stratIdx = autoStrategy.s
    endif
    @strategy: stratIdx
    stratName$ = stratName$ + " (auto)"
elsif spatial_strategy = 14
    @strategy: 2
    stratName$ = "Custom mapping"
else
    @strategy: spatial_strategy
endif

# ============================================================
# DETAIL DIALOGS
# ============================================================
if show_details
    beginPause: "Spatial Dramaturgy — dramaturgy and behaviour"
        comment: "Archetype"
        real: "Archetype strength (0-1)", string$(archStrength)
        comment: "Analysis weights (Analyze source)"
        real: "Intensity", string$(wInt)
        real: "Brightness", string$(wBright)
        real: "Spectral change", string$(wChange)
        real: "Activity density", string$(wDensity)
        real: "Noisiness", string$(wNoise)
        real: "Pitch instability", string$(wPitch)
        positive: "Smoothing (s)", string$(smoothSec)
        real: "Analysis sensitivity", string$(analysisSens)
        comment: "Behaviour and output"
        optionMenu: "Fragmentation method", fragMethod
            option: "Frequency bands"
            option: "Temporal slices"
            option: "Delayed copies"
        positive: "Max rotation speed (deg per s)", string$(maxSpeed)
        natural: "Speakers in custom ring", string$(ringN)
        optionMenu: "Normalization", normMode
            option: "Peak -1 dBFS"
            option: "None (protect against clipping only)"
        boolean: "Measure output energy panel", measureEnergy
    endPause: "Continue", 1
    archStrength = archetype_strength
    wInt = intensity
    wBright = brightness
    wChange = spectral_change
    wDensity = activity_density
    wNoise = noisiness
    wPitch = pitch_instability
    smoothSec = smoothing
    analysisSens = analysis_sensitivity
    fragMethod = fragmentation_method
    maxSpeed = max_rotation_speed
    ringN = speakers_in_custom_ring
    normMode = normalization
    measureEnergy = measure_output_energy_panel
endif
if show_details or spatial_strategy = 14
    beginPause: "Spatial Dramaturgy — mapping (min max dir curve influence)"
        comment: "dir: + positive, - inverted, = fixed at min;  curve: lin exp log sig thr step rnd"
        sentence: "Spread", map1$
        sentence: "Distance", map2$
        sentence: "Movement rate", map3$
        sentence: "Irregularity", map4$
        sentence: "Elevation", map5$
        sentence: "Peripheral", map6$
        sentence: "Fragmentation", map7$
    endPause: "Continue", 1
    map1$ = spread$
    map2$ = distance$
    map3$ = movement_rate$
    map4$ = irregularity$
    map5$ = elevation$
    map6$ = peripheral$
    map7$ = fragmentation$
endif

# ---- parse and validate the mappings ----
dimName1$ = "Spread"
dimName2$ = "Distance"
dimName3$ = "Movement rate"
dimName4$ = "Irregularity"
dimName5$ = "Elevation"
dimName6$ = "Peripheral"
dimName7$ = "Fragmentation"
for zd to 7
    line$ = replace_regex$(map'zd'$, "^[ \t]+|[ \t]+$", "", 0)
    line$ = replace_regex$(line$, "[ \t]+", " ", 0)
    nTok = 0
    rest$ = line$ + " "
    while index(rest$, " ") > 0 and length(rest$) > 1
        nTok = nTok + 1
        tok_'nTok'$ = left$(rest$, index(rest$, " ") - 1)
        rest$ = mid$(rest$, index(rest$, " ") + 1, length(rest$))
    endwhile
    if nTok <> 5
        exitScript: dimName'zd'$ + " mapping needs 5 items (min max dir curve influence), got: " + map'zd'$
    endif
    mapMin_'zd' = number(tok_1$)
    mapMax_'zd' = number(tok_2$)
    mapInf_'zd' = number(tok_5$)
    if mapMin_'zd' = undefined or mapMax_'zd' = undefined or mapInf_'zd' = undefined
        exitScript: dimName'zd'$ + " mapping: min, max and influence must be numbers: " + map'zd'$
    endif
    mapMin_'zd' = max(0, min(1, mapMin_'zd'))
    mapMax_'zd' = max(0, min(1, mapMax_'zd'))
    mapInf_'zd' = max(0, min(1, mapInf_'zd'))
    if tok_3$ = "+"
        mapDir_'zd' = 1
    elsif tok_3$ = "-"
        mapDir_'zd' = -1
    elsif tok_3$ = "="
        mapDir_'zd' = 0
    else
        exitScript: dimName'zd'$ + " mapping: direction must be +, - or = (got " + tok_3$ + ")"
    endif
    mapCurve_'zd' = 0
    for zq to 7
        if tok_4$ = {"lin", "exp", "log", "sig", "thr", "step", "rnd"} [zq]
            mapCurve_'zd' = zq
        endif
    endfor
    if mapCurve_'zd' = 0
        exitScript: dimName'zd'$ + " mapping: curve must be lin exp log sig thr step or rnd (got " + tok_4$ + ")"
    endif
endfor
charK = 0.35
charName$ = "Subtle"
if character = 2
    charK = 0.6
    charName$ = "Moderate"
elsif character = 3
    charK = 0.85
    charName$ = "Dramatic"
elsif character = 4
    charK = 1.0
    charName$ = "Radical"
endif
archStrength = max(0, min(1, archStrength))
smoothSec = max(0.05, smoothSec)
analysisSens = max(0, min(4, analysisSens))
maxSpeed = max(0, min(720, maxSpeed))
ringN = max(3, min(32, ringN))

# ============================================================
# SOURCE (working copy; the original is never modified)
# ============================================================
selectObject: srcObjOrig
srcCh = Get number of channels
src = Copy: "sdc_src"
Shift times to: "start time", 0
monoNote$ = "mono"
if srcCh > 1
    tmpM = Convert to mono
    removeObject: src
    src = tmpM
    monoNote$ = string$(srcCh) + " channels averaged to mono (the spatialisation re-creates the image)"
endif
selectObject: src
dur = Get total duration
sr = Get sampling frequency
srcRms = Get root-mean-square: 0, 0
if dur < 0.5
    removeObject: src
    exitScript: "The source is shorter than 0.5 s; spatial form needs some time to unfold."
endif
if srcRms = undefined or srcRms < 1e-9
    removeObject: src
    exitScript: "The source is silent."
endif

# ============================================================
# DRAMATURGY CURVE D(t) -> RealTier "Dramaturgy_<name>"
# ============================================================
procedure archetypeValue: .a, .u
    # macro-form shapes on normalised time u (0..1), value 0..1
    .ss = .u * .u * (3 - 2 * .u)
    if .a = 1
        .v = .ss
    elsif .a = 2
        .v = 1 - .ss
    elsif .a = 3
        .v = sin(pi * .u)
    elsif .a = 4
        .v = 1 - sin(pi * .u)
    elsif .a = 5
        .v = .u ^ 1.5
    elsif .a = 6
        .v = 1 - .u ^ 0.7
    elsif .a = 7
        # four stations (front, lateral, rear, surrounding) with transitions
        .q = min(3.999, 4 * .u)
        .f = .q - floor(.q)
        .tr = max(0, min(1, (.f - 0.6) / 0.4))
        .v = min(1, (floor(.q) + .tr * .tr * (3 - 2 * .tr)) / 3)
    elsif .a = 8
        .t = max(0, min(1, (.u - 0.4) / 0.4))
        .v = .t * .t * (3 - 2 * .t)
    elsif .a = 9
        .t = max(0, min(1, .u / 0.6))
        .v = 1 - .t * .t * (3 - 2 * .t)
    elsif .a = 10
        .v = .ss ^ 0.7
    elsif .a = 11
        .q = min(5.999, 6 * .u)
        .v = (floor(.q) + 0.5 * (.q - floor(.q))) / 6
    elsif .a = 12
        # mostly stable, abrupt rupture at 62% with a short aftershock
        .v = 0.15
        if .u >= 0.62
            .v = 0.15 + 0.85 * exp(-(.u - 0.62) / 0.06)
        endif
        if .u >= 0.8
            .v = .v + 0.35 * exp(-(.u - 0.8) / 0.03)
        endif
        .v = min(1, .v)
    elsif .a = 13
        .v = 0.5 - 0.5 * cos(2 * pi * 3 * .u)
    else
        # chaotic escalation is computed by the caller (needs archNoiseAt)
        .v = .u
    endif
endproc

# smooth seeded noise for Chaotic Escalation (sum of fixed random partials)
random_initializeWithSeedUnsafelyButPredictably: seed
for zp to 6
    anFreq_'zp' = randomUniform(3, 14)
    anPhase_'zp' = randomUniform(0, 2 * pi)
endfor
random_initializeSafelyAndUnpredictably ()
procedure archNoiseAt: .u
    .s = 0
    for zp to 6
        .s = .s + sin(2 * pi * anFreq_'zp' * .u + anPhase_'zp') / zp
    endfor
    .v = .s * 0.45
endproc

dTier = Create RealTier: "Dramaturgy_" + srcName$, 0, dur
dSourceName$ = ""
if dramaturgy = 3
    dSourceName$ = "Archetype " + archetype$
    for zi from 0 to 200
        u = zi / 200
        if archetype = 14
            @archNoiseAt: u
            av = u + u * archNoiseAt.v
            av = max(0, min(1, av))
        else
            @archetypeValue: archetype, u
            av = archetypeValue.v
        endif
        av = 0.5 + archStrength * (av - 0.5)
        selectObject: dTier
        Add point: u * dur, av
    endfor
elsif dramaturgy = 1
    if userTier <> 0
        dSourceName$ = "Drawn (selected RealTier)"
        selectObject: userTier
        nUp = Get number of points
        if nUp < 1
            exitScript: "The selected RealTier has no points."
        endif
        for zi from 0 to 200
            selectObject: userTier
            v = Get value at time: zi / 200 * dur
            selectObject: dTier
            Add point: zi / 200 * dur, max(0, min(1, v))
        endfor
    else
        dSourceName$ = "Drawn (edited curve)"
        # starting shape: an arch; edit it, then press Continue
        selectObject: dTier
        Add point: 0, 0.1
        Add point: 0.3 * dur, 0.4
        Add point: 0.6 * dur, 0.95
        Add point: 0.85 * dur, 0.6
        Add point: dur, 0.1
        View & Edit
        beginPause: "Draw the dramaturgy"
            comment: "Edit the RealTier (values 0 = calm ... 1 = maximal dramaturgical intensity)."
            comment: "Add / move points in the editor window, then press Continue."
        endPause: "Continue", 1
        selectObject: dTier
        nUp = Get number of points
        if nUp < 1
            exitScript: "The dramaturgy curve has no points."
        endif
    endif
else
    dSourceName$ = "Analysis of the source"
    @analyzeSource
endif

procedure analyzeSource
    # descriptors on a 0.1 s grid, robustly normalised (5th-95th
    # percentile), weighted, summed, normalised to 0..1, then smoothed
    .hop = 0.1
    .nF = max(2, floor(dur / .hop))
    selectObject: src
    .int = To Intensity: 75, 0.02, "no"
    selectObject: src
    .harm = To Harmonicity (cc): 0.02, 75, 0.1, 1.0
    if wPitch > 0
        selectObject: src
        .pit = To Pitch: 0.02, 75, 800
    endif
    .prevOk = 0
    for zf to .nF
        .t = (zf - 0.5) * .hop
        selectObject: .int
        .iv = Get mean: max(0, .t - .hop / 2), min(dur, .t + .hop / 2), "energy"
        dsc_1_'zf' = if .iv = undefined then -100 else .iv fi
        # spectrum of a Hann-windowed 0.1 s frame
        selectObject: src
        .seg = Extract part: max(0, .t - 0.05), min(dur, .t + 0.05), "Hanning", 1, "no"
        .spc = To Spectrum: "yes"
        .cog = Get centre of gravity: 2
        dsc_2_'zf' = if .cog = undefined then 0 else .cog fi
        .flux = 0
        # Nyquist-safe logarithmic bands. At ordinary sample rates this is
        # 50 Hz..min(16 kHz, 0.95 Nyquist); at very low rates the lower bound
        # is reduced as well, so no band starts above Nyquist.
        .fMax = max(1, min(16000, 0.95 * sr / 2))
        .fMin = min(50, .fMax / 4)
        for zb to 10
            .f1 = .fMin * (.fMax / .fMin) ^ ((zb - 1) / 10)
            .f2 = .fMin * (.fMax / .fMin) ^ (zb / 10)
            .be = Get band energy: .f1, .f2
            .lb = 10 * log10(max(.be, 1e-20))
            if .prevOk
                .flux = .flux + abs(.lb - prevBand_'zb')
            endif
            prevBand_'zb' = .lb
        endfor
        .prevOk = 1
        dsc_3_'zf' = .flux
        removeObject: .seg, .spc
        # activity density: positive 3 dB steps of the 20 ms intensity in +-0.5 s
        .cnt = 0
        selectObject: .int
        .t0 = max(0.02, .t - 0.5)
        .t1 = min(dur - 0.02, .t + 0.5)
        .tt = .t0
        .last = Get value at time: .tt, "cubic"
        while .tt < .t1
            .tt = .tt + 0.02
            .now = Get value at time: .tt, "cubic"
            if .now <> undefined and .last <> undefined
                if .now - .last > 3
                    .cnt = .cnt + 1
                endif
            endif
            .last = .now
        endwhile
        dsc_4_'zf' = .cnt
        # noisiness from HNR (below -60 dB = unmeasurable, treated as noise)
        selectObject: .harm
        .h = Get mean: max(0, .t - .hop / 2), min(dur, .t + .hop / 2)
        if .h = undefined or .h < -60
            .h = -10
        endif
        dsc_5_'zf' = -.h
        # pitch instability (semitone deviation in +-0.25 s), optional
        dsc_6_'zf' = 0
        if wPitch > 0
            selectObject: .pit
            .sd = Get standard deviation: max(0, .t - 0.25), min(dur, .t + 0.25), "semitones"
            dsc_6_'zf' = if .sd = undefined then 0 else .sd fi
        endif
    endfor
    removeObject: .int, .harm
    if wPitch > 0
        removeObject: .pit
    endif
    # robust normalisation per descriptor
    for zk to 6
        # 5th / 95th percentiles via a sorted vector
        .vec# = zero# (.nF)
        for zf to .nF
            .vec# [zf] = dsc_'zk'_'zf'
        endfor
        .srt# = sort# (.vec#)
        .lo = .srt# [max(1, round(0.05 * .nF))]
        .hi = .srt# [max(1, round(0.95 * .nF))]
        .rg = .hi - .lo
        for zf to .nF
            if .rg > 1e-12
                ndsc_'zk'_'zf' = max(0, min(1, (dsc_'zk'_'zf' - .lo) / .rg))
            else
                ndsc_'zk'_'zf' = 0
            endif
        endfor
    endfor
    .wsum = wInt + wBright + wChange + wDensity + wNoise + wPitch
    if .wsum <= 0
        exitScript: "All analysis weights are zero."
    endif
    for zf to .nF
        raw_'zf' = (wInt * ndsc_1_'zf' + wBright * ndsc_2_'zf' + wChange * ndsc_3_'zf' + wDensity * ndsc_4_'zf' + wNoise * ndsc_5_'zf' + wPitch * ndsc_6_'zf') / .wsum
    endfor
    # smoothing: moving average over smoothSec. The result is NOT stretched
    # to 0..1 again (v1.0 did, so a nearly static source could still produce
    # a full 0..1 excursion). Each descriptor is already 5-95 percentile
    # normalised; the weighted mean keeps the source's own contrast, and
    # Analysis sensitivity scales it around its mean (1 = as measured).
    .k = max(1, round(smoothSec / .hop / 2))
    .mn = 1e9
    .mx = -1e9
    .mean = 0
    for zf to .nF
        .s = 0
        .c = 0
        for zq from max(1, zf - .k) to min(.nF, zf + .k)
            .s = .s + raw_'zq'
            .c = .c + 1
        endfor
        sm_'zf' = .s / .c
        .mn = min(.mn, sm_'zf')
        .mx = max(.mx, sm_'zf')
        .mean = .mean + sm_'zf' / .nF
    endfor
    selectObject: dTier
    for zf to .nF
        .v = max(0, min(1, .mean + analysisSens * (sm_'zf' - .mean)))
        Add point: (zf - 0.5) * .hop, .v
    endfor
    analysisRange$ = fixed$(max(0, min(1, .mean + analysisSens * (.mn - .mean))), 2) + " - " + fixed$(max(0, min(1, .mean + analysisSens * (.mx - .mean))), 2)
    analysisNote$ = "weights int " + fixed$(wInt, 2) + ", bright " + fixed$(wBright, 2) + ", change " + fixed$(wChange, 2) + ", density " + fixed$(wDensity, 2) + ", noise " + fixed$(wNoise, 2) + ", pitch " + fixed$(wPitch, 2) + "; smoothing " + fixed$(smoothSec, 1) + " s; sensitivity " + fixed$(analysisSens, 2) + "; D range " + analysisRange$
endproc

# ============================================================
# SPATIAL STATE: D(t) -> seven dimensions at the control rate
# ============================================================
fc = 50
dtc = 1 / fc
nFr = max(2, round(dur * fc))

procedure response: .c, .x
    if .c = 1
        .y = .x
    elsif .c = 2
        .y = (exp(3 * .x) - 1) / (exp(3) - 1)
    elsif .c = 3
        .y = ln(1 + 9 * .x) / ln(10)
    elsif .c = 4
        .y = (1 / (1 + exp(-10 * (.x - 0.5))) - 1 / (1 + exp(5))) / (1 / (1 + exp(-5)) - 1 / (1 + exp(5)))
    elsif .c = 5
        .t = max(0, min(1, (.x - 0.6) / 0.15))
        .y = .t * .t * (3 - 2 * .t)
    elsif .c = 6
        .y = min(1, floor(.x * 4) / 3)
    else
        # randomised around the curve: seeded smooth deviation
        .y = max(0, min(1, .x + 0.15 * rndDev))
    endif
endproc

# maps D through dimension zdim (GLOBAL index: 'x' interpolation cannot see
# dotted procedure locals)
procedure mapDimG: .dv
    if mapDir_'zdim' = 0
        .v = mapMin_'zdim'
    else
        .x = .dv
        if mapDir_'zdim' < 0
            .x = 1 - .dv
        endif
        @response: mapCurve_'zdim', .x
        .v = mapMin_'zdim' + (mapMax_'zdim' - mapMin_'zdim') * mapInf_'zdim' * response.y
    endif
endproc

# rest state (D = 0) per dimension; Character scales the excursion from it
rndDev = 0
for zdim to 7
    @mapDimG: 0
    rest_'zdim' = mapDimG.v
endfor

random_initializeWithSeedUnsafelyButPredictably: seed + 101
rndState = 0
rndRho = exp(-dtc / 1.5)
peakD = -1
peakT = 0
for zf to nFr
    t = (zf - 0.5) * dtc
    selectObject: dTier
    dval = Get value at time: t
    dval = max(0, min(1, dval))
    dd_'zf' = dval
    if dval > peakD
        peakD = dval
        peakT = t
    endif
    rndState = rndRho * rndState + sqrt(1 - rndRho * rndRho) * randomGauss(0, 1)
    rndDev = rndState
    for zdim to 7
        @mapDimG: dval
        st_'zdim'_'zf' = rest_'zdim' + charK * (mapDimG.v - rest_'zdim')
    endfor
endfor
random_initializeSafelyAndUnpredictably ()
# the dramaturgy now lives in the control arrays; the RealTier was only a
# carrier (a RealTier the user selected is never touched)
removeObject: dTier

# ============================================================
# SPEAKERS
# ============================================================
ambi = 0
if output = 1
    nCh = 2
    spkAz_1 = -30
    spkAz_2 = 30
    layoutName$ = "stereo (L/R amplitude panning, front-rear folded)"
elsif output = 2
    nCh = 4
    spkAz_1 = -45
    spkAz_2 = 45
    spkAz_3 = -135
    spkAz_4 = 135
    layoutName$ = "quad FL FR RL RR (amplitude panning)"
elsif output = 3
    nCh = 8
    for zs to 8
        spkAz_'zs' = -22.5 + (zs - 1) * 45
    endfor
    layoutName$ = "8-channel ring, clockwise from front-left (amplitude panning)"
elsif output = 4
    nCh = ringN
    for zs to nCh
        spkAz_'zs' = -180 / nCh + (zs - 1) * 360 / nCh
    endfor
    layoutName$ = string$(nCh) + "-speaker ring, clockwise from the front-left speaker (amplitude panning)"
else
    nCh = 4
    ambi = 1
    layoutName$ = "first-order Ambisonic encoding, AmbiX (ACN W Y Z X, SN3D), no decoder"
endif
spk = Create simple Matrix: "sdc_spk", max(nCh, 1), 1, "0"
if not ambi
    for zs to nCh
        Set value: zs, 1, spkAz_'zs'
    endfor
endif
dlt = 360 / nCh

# ============================================================
# TRAJECTORY REALISATION (control rate, seeded)
# ============================================================
nAg = maxAgents
# Agents: 1 = centre; then MIRRORED PAIRS (2,3) = +-1, (4,5) = +-0.5,
# (6,7) = +-0.75, released together so the field opens symmetrically; with
# an even count the last agent has no partner. Pairs also spin and drift
# to the periphery in mirror image. A single centre source has to leave the
# front towards one side: that side is chosen by the seed, not fixed right.
side1 = if seed mod 2 = 0 then 1 else -1 fi
nGroups = floor(nAg / 2)
pairOff# = {1, 0.5, 0.75}
pairSpin# = {1.2, 0.7, 1.6}
for zj to nAg
    if zj = 1
        agOff_'zj' = 0
        agSpin_'zj' = 1
        agSide_'zj' = side1
        agGroup_'zj' = 0
    elsif zj = nAg and nAg mod 2 = 0
        # unpaired last agent: opposite side to agent 1, released last
        agOff_'zj' = -side1
        agSpin_'zj' = -1
        agSide_'zj' = -side1
        agGroup_'zj' = nGroups
    else
        # pair k = floor(j / 2): even j on the + side, odd j mirrored
        pk = floor(zj / 2)
        sg = if zj mod 2 = 0 then 1 else -1 fi
        agOff_'zj' = sg * pairOff# [pk]
        agSpin_'zj' = sg * pairSpin# [pk]
        agSide_'zj' = sg
        agGroup_'zj' = pk
    endif
    agPhase_'zj' = 0
    agNz_'zj' = 0
    agNe_'zj' = 0
    agNr_'zj' = 0
    agNq_'zj' = 0
endfor
# control objects: pos (az 1..N, el N+1..2N), ctl (diffuse, distance gain, release 3..N+2)
pos = Create Sound from formula: "sdc_pos", 2 * nAg, 0, nFr / fc, fc, "0"
ctl = Create Sound from formula: "sdc_ctl", 2 + nAg, 0, nFr / fc, fc, "0"
random_initializeWithSeedUnsafelyButPredictably: seed
rhoN = exp(-dtc / 0.6)
rho2 = exp(-dtc / 0.3)
# variance of AR(1) (unit) after a one-pole: (1-r2)/(1+r2) * (1+r1 r2)/(1-r1 r2)
nzGain = 1 / sqrt((1 - rho2) / (1 + rho2) * (1 + rhoN * rho2) / (1 - rhoN * rho2))
maxActive = 1
for zf to nFr
    sSpread = st_1_'zf'
    sDist = st_2_'zf'
    sRate = st_3_'zf'
    sIrr = st_4_'zf'
    sElev = st_5_'zf'
    sPer = st_6_'zf'
    sFrag = st_7_'zf'
    act = 1
    for zj to nAg
        # independent rotation: coherent at fragmentation 0, own spin at 1
        agPhase_'zj' = agPhase_'zj' + sRate * maxSpeed * dtc * (1 + sFrag * (agSpin_'zj' - 1))
        # irregularity: two cascaded smoothing stages (AR(1), tau 0.6 s, then a
        # 0.3 s one-pole, amplitude-compensated) -> smooth wandering, not jitter
        agNr_'zj' = rhoN * agNr_'zj' + sqrt(1 - rhoN * rhoN) * randomGauss(0, 1)
        agNz_'zj' = rho2 * agNz_'zj' + (1 - rho2) * agNr_'zj' * nzGain
        agNq_'zj' = rhoN * agNq_'zj' + sqrt(1 - rhoN * rhoN) * randomGauss(0, 1)
        agNe_'zj' = rho2 * agNe_'zj' + (1 - rho2) * agNq_'zj' * nzGain
        # peripheralisation, continuous everywhere: (1) each agent's home moves
        # from the front towards its own side (odd agents right, even left);
        # (2) a smooth circle map pushes positions away from the front:
        # theta' = 2 atan2(k sin(theta/2), cos(theta/2)), k = 1 + 3P, which
        # keeps 0 and 180 deg fixed and has no jump anywhere (v0 drafts warped
        # |theta| directly and made agents jump from -90 to +90 at the front)
        home = agSide_'zj' * sPer * 110
        az = home + sSpread * 180 * agOff_'zj' + agPhase_'zj' + sIrr * 90 * agNz_'zj'
        az = ((az + 180) mod 360) - 180
        kap = 1 + 3 * sPer
        az = 2 * arctan2(kap * sin(az * pi / 360), cos(az * pi / 360)) * 180 / pi
        el = max(0, min(90, sElev * 75 + sIrr * 15 * agNe_'zj'))
        selectObject: pos
        Set value at sample number: zj, zf, az
        Set value at sample number: nAg + zj, zf, el
        agAz_'zj'_'zf' = az
        agEl_'zj'_'zf' = el
        # release of agent j (j >= 2) as fragmentation rises
        rel = 1
        if zj > 1
            rel = max(0, min(1, (sFrag - (agGroup_'zj' - 1) / nGroups) * nGroups))
            act = act + rel
        endif
        agRel_'zj'_'zf' = rel
        selectObject: ctl
        Set value at sample number: 2 + zj, zf, rel
    endfor
    nActive_'zf' = act
    maxActive = max(maxActive, act)
    # distance: attenuation and diffuseness; elevation adds diffuseness on rings
    dif = 0.6 * sDist
    if not ambi
        dif = dif + 0.35 * sElev
    endif
    dif = max(0, min(0.9, dif))
    selectObject: ctl
    Set value at sample number: 1, zf, dif
    Set value at sample number: 2, zf, 1 / (1 + 2 * sDist)
endfor
random_initializeSafelyAndUnpredictably ()

# control envelopes are read between their first and last point: Praat's
# time-based object() lookup interpolates toward zero outside the sample
# centres, which faded the first and last 10 ms of every render
xc0 = dtc / 2
xc1 = (nFr - 0.5) * dtc

# ============================================================
# AGENT SIGNALS (partition of the source; no full-level duplicates)
# ============================================================
if nAg = 1
    agents = Create Sound from formula: "sdc_agents", 1, 0, dur, sr, "object [src, 1, col]"
    fragName$ = "single agent"
elsif fragMethod = 1
    # log-spaced bands; agent 1 keeps band 1 and everything not yet released
    # every band uses the SAME crossfade width, so neighbouring Hann bands
    # are complementary and the bands sum back to the source
    # one forward FFT of the source; each band = a filtered copy of that
    # Spectrum, transformed back and trimmed to the source length
    fTop = min(16000, sr / 2 * 0.95)
    bandSmooth = 30
    selectObject: src
    srcSpec = To Spectrum: "yes"
    for zj to nAg
        fLo = 0
        if zj > 1
            fLo = 80 * (fTop / 80) ^ ((zj - 1) / nAg)
        endif
        fHi = 0
        if zj < nAg
            fHi = 80 * (fTop / 80) ^ (zj / nAg)
        endif
        selectObject: srcSpec
        tmpSp = Copy: "sdc_bandspec"
        Filter (pass Hann band): fLo, fHi, bandSmooth
        tmpLong = To Sound
        band_'zj' = Extract part: 0, dur, "rectangular", 1, "no"
        removeObject: tmpSp, tmpLong
    endfor
    removeObject: srcSpec
    bandF$ = ""
    for zj to nAg
        if zj > 1
            bandF$ = bandF$ + " else "
        endif
        bandF$ = bandF$ + "if row = " + string$(zj) + " then object [band_" + string$(zj) + ", 1, col]"
    endfor
    bandF$ = bandF$ + " else 0"
    for zj to nAg
        bandF$ = bandF$ + " fi"
    endfor
    bands = Create Sound from formula: "sdc_bands", nAg, 0, dur, sr, bandF$
    for zj to nAg
        removeObject: band_'zj'
    endfor
    relSum$ = ""
    for zj from 2 to nAg
        relSum$ = relSum$ + " + object (ctl, min (max (x, xc0), xc1), " + string$(2 + zj) + ") * object [bands, " + string$(zj) + ", col]"
    endfor
    agents = Create Sound from formula: "sdc_agents", nAg, 0, dur, sr, "if row = 1 then object [src, 1, col] - (0" + relSum$ + ") else object (ctl, min (max (x, xc0), xc1), 2 + row) * object [bands, row, col] fi"
    removeObject: bands
    fragName$ = "frequency bands (agent 1 = whole sound minus released bands)"
elsif fragMethod = 2
    sliceL = 0.25
    gate$ = "(if min (abs (((x / sliceL) mod nAg) - (row - 1)), nAg - abs (((x / sliceL) mod nAg) - (row - 1))) < 1 then cos (pi / 2 * min (abs (((x / sliceL) mod nAg) - (row - 1)), nAg - abs (((x / sliceL) mod nAg) - (row - 1)))) ^ 2 else 0 fi)"
    relSum$ = ""
    for zj from 2 to nAg
        g$ = replace$(gate$, "(row - 1)", string$(zj - 1), 0)
        relSum$ = relSum$ + " + object (ctl, min (max (x, xc0), xc1), " + string$(2 + zj) + ") * " + g$
    endfor
    agents = Create Sound from formula: "sdc_agents", nAg, 0, dur, sr, "if row = 1 then object [src, 1, col] * (1 - (0" + relSum$ + ")) else object (ctl, min (max (x, xc0), xc1), 2 + row) * " + gate$ + " * object [src, 1, col] fi"
    fragName$ = "temporal slices (" + fixed$(sliceL * 1000, 0) + " ms, cos^2 crossfades; slices sum to the source)"
else
    dl# = {0, 7, 11, 13, 17, 19, 23, 29}
    # Gain normalisation: agent gains are 1 (agent 1) and r_j. Dividing by
    # sqrt(1 + sum r_j^2) is power-neutral only if the delayed copies are
    # sufficiently decorrelated; tonal material may still reinforce/cancel.
    relSum$ = "1"
    for zj from 2 to nAg
        relSum$ = relSum$ + " + object (ctl, min (max (x, xc0), xc1), " + string$(2 + zj) + ") ^ 2"
    endfor
    for zj to nAg
        dlS_'zj' = round(dl# [zj] / 1000 * sr)
    endfor
    dlF$ = ""
    for zj to nAg
        if zj > 1
            dlF$ = dlF$ + " else "
        endif
        dlF$ = dlF$ + "if row = " + string$(zj) + " then object [src, 1, col - " + string$(dlS_'zj') + "]"
    endfor
    dlF$ = dlF$ + " else 0"
    for zj to nAg
        dlF$ = dlF$ + " fi"
    endfor
    agents = Create Sound from formula: "sdc_agents", nAg, 0, dur, sr, "(if row = 1 then 1 else object (ctl, min (max (x, xc0), xc1), 2 + row) fi) / sqrt (" + relSum$ + ") * (" + dlF$ + ")"
    fragName$ = "delayed copies (7-29 ms, gain-normalised; power-neutral only under a decorrelated-copy assumption)"
endif

# ============================================================
# GAINS (agent x channel, control rate) and RENDERING
# ============================================================
# gain row r: agent j = (r-1) div nCh + 1, channel c = (r-1) mod nCh + 1
if ambi
    gainF$ = "object [ctl, 2, col] * (if ((row - 1) mod 4) = 0 then 1 else (1 - object [ctl, 1, col]) * (if ((row - 1) mod 4) = 1 then - sin (object [pos, (row - 1) div 4 + 1, col] * pi / 180) * cos (object [pos, nAg + (row - 1) div 4 + 1, col] * pi / 180) else if ((row - 1) mod 4) = 2 then sin (object [pos, nAg + (row - 1) div 4 + 1, col] * pi / 180) else cos (object [pos, (row - 1) div 4 + 1, col] * pi / 180) * cos (object [pos, nAg + (row - 1) div 4 + 1, col] * pi / 180) fi fi) fi)"
else
    # Speaker layouts. Direct gains g_c are equal-power (sum g_c^2 = 1). The
    # diffuse part is the SAME signal at d / sqrt(N) on every speaker, so the
    # blend a g_c + b (a = sqrt(1 - d^2), b = d / sqrt(N)) has power
    # 1 + 2 a b sum(g_c), not 1 (up to +3 dB in stereo at d = 0.71; and on
    # rings elevation is rendered as diffuseness, so height sounded louder).
    # Each agent's gains are therefore divided by sqrt(1 + 2 a b sum g_c),
    # which makes the total power exactly the distance gain squared.
    if nCh = 2
        gdirF$ = "if ((row - 1) mod 2) = 0 then cos ((sin (object [pos, (row - 1) div 2 + 1, col] * pi / 180) + 1) * pi / 4) else sin ((sin (object [pos, (row - 1) div 2 + 1, col] * pi / 180) + 1) * pi / 4) fi"
    else
        dist$ = "abs (((object [pos, (row - 1) div nCh + 1, col] - object [spk, ((row - 1) mod nCh) + 1, 1] + 180) mod 360) - 180)"
        gdirF$ = "if " + dist$ + " < dlt then cos (pi / 2 * " + dist$ + " / dlt) else 0 fi"
    endif
    gdir = Create Sound from formula: "sdc_gdir", nAg * nCh, 0, nFr / fc, fc, gdirF$
    gsumF$ = ""
    for zc to nCh
        if zc > 1
            gsumF$ = gsumF$ + " + "
        endif
        gsumF$ = gsumF$ + "object [gdir, (row - 1) * nCh + " + string$(zc) + ", col]"
    endfor
    gsum = Create Sound from formula: "sdc_gsum", nAg, 0, nFr / fc, fc, gsumF$
    gainF$ = "object [ctl, 2, col] * (sqrt (1 - object [ctl, 1, col] ^ 2) * object [gdir, row, col] + object [ctl, 1, col] / sqrt (nCh)) / sqrt (1 + 2 * sqrt (1 - object [ctl, 1, col] ^ 2) * object [ctl, 1, col] / sqrt (nCh) * object [gsum, (row - 1) div nCh + 1, col])"
endif
gains = Create Sound from formula: "sdc_gains", nAg * nCh, 0, nFr / fc, fc, gainF$
if not ambi
    removeObject: gdir, gsum
endif
renderF$ = ""
for zj to nAg
    if zj > 1
        renderF$ = renderF$ + " + "
    endif
    renderF$ = renderF$ + "object [agents, " + string$(zj) + ", col] * object (gains, min (max (x, xc0), xc1), " + string$((zj - 1) * nCh) + " + row)"
endfor
stopwatch
outName$ = srcName$ + "_SpatialDramaturgy_" + replace_regex$(stratName$, "[^A-Za-z0-9]", "", 0)
out = Create Sound from formula: outName$, nCh, 0, dur, sr, renderF$
renderTime = stopwatch

# ---- level: optional peak normalisation, always clipping protection ----
rawPeak = Get absolute extremum: 0, 0, "None"
normNote$ = "none"
if rawPeak > 1e-9
    if normMode = 1
        Scale peak: 10 ^ (-1 / 20)
        normNote$ = "peak to -1 dBFS"
    elsif rawPeak > 0.999
        Formula: "self * 0.999 / rawPeak"
        normNote$ = "attenuated " + fixed$(20 * log10(0.999 / rawPeak), 1) + " dB to avoid clipping"
    endif
endif
outPeak = Get absolute extremum: 0, 0, "None"

# ---- maxima for the report ----
for zdim to 7
    mx_'zdim' = -1
    for zf to nFr
        mx_'zdim' = max(mx_'zdim', st_'zdim'_'zf')
    endfor
endfor

# ============================================================
# REPORT
# ============================================================
fragMethodName$ = fragName$
writeInfoLine: "=== Spatial Dramaturgy Composer v", version$, " ==="
appendInfoLine: "Source:            ", srcName$, "  (", fixed$(dur, 2), " s, ", sr, " Hz; ", monoNote$, ")"
appendInfoLine: "Dramaturgy:        ", dSourceName$
if dramaturgy = 2
    appendInfoLine: "                   ", analysisNote$
endif
appendInfoLine: "Spatial strategy:  ", stratName$, "   character ", charName$, " (excursion x", fixed$(charK, 2), ")"
for zdim to 7
    appendInfoLine: "   ", left$(dimName'zdim'$ + "              ", 14), map'zdim'$, "    max ", fixed$(mx_'zdim', 2)
endfor
appendInfoLine: "Renderer:          ", layoutName$, ", ", nCh, " channels"
if not ambi and mx_5 > 0.01
    appendInfoLine: "                   elevation cannot be reproduced on a horizontal ring: rendered as added diffuseness only"
endif
appendInfoLine: "Distance:          amplitude 1/(1+2d) and direct/diffuse blend; no propagation delay, air absorption or room"
appendInfoLine: "Spatial agents:    up to ", nAg, " (", fragMethodName$, "); maximum active ", fixed$(maxActive, 1)
appendInfoLine: "Peak dramaturgy:   ", fixed$(peakD, 2), " at ", fixed$(peakT, 1), " s"
appendInfoLine: "Random seed:       ", seed
appendInfoLine: "Level:             ", normNote$, "; output peak ", fixed$(outPeak, 3), "; rendering ", fixed$(renderTime, 1), " s"
appendInfoLine: "Object:            ", outName$

if draw_visualisation
    @drawFigure
endif
removeObject: src, pos, ctl, agents, gains, spk
selectObject: out
if play_result
    Play
endif

# ============================================================
# FIGURE — a spatial score
# ============================================================
procedure niceStep: .span, .n
    .raw = .span / .n
    if .raw <= 0
        .raw = 1
    endif
    .p = 10 ^ floor(log10(.raw))
    .m = .raw / .p
    if .m < 1.5
        .step = .p
    elsif .m < 3.5
        .step = 2 * .p
    elsif .m < 7.5
        .step = 5 * .p
    else
        .step = 10 * .p
    endif
endproc

procedure railLabel: .y0, .y1, .name$
    Font size: 7
    Select inner viewport: 0.6, 7.7, .y0, .y1
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text special: -0.068, "centre", 0.5, "bottom", "Helvetica", 7, "90", .name$
endproc

procedure dimColour: .i
    .rgb$ = "{0.20, 0.40, 0.80}"
    if .i = 2
        .rgb$ = "{0.45, 0.45, 0.45}"
    elsif .i = 3
        .rgb$ = "{0.85, 0.35, 0.15}"
    elsif .i = 4
        .rgb$ = "{0.75, 0.20, 0.45}"
    elsif .i = 5
        .rgb$ = "{0.15, 0.60, 0.35}"
    elsif .i = 6
        .rgb$ = "{0.85, 0.65, 0.10}"
    elsif .i = 7
        .rgb$ = "{0.60, 0.25, 0.70}"
    endif
endproc

procedure agColour: .j
    .rgb$ = "{0.20, 0.40, 0.80}"
    if .j = 2
        .rgb$ = "{0.85, 0.35, 0.15}"
    elsif .j = 3
        .rgb$ = "{0.15, 0.60, 0.35}"
    elsif .j = 4
        .rgb$ = "{0.60, 0.25, 0.70}"
    elsif .j = 5
        .rgb$ = "{0.85, 0.65, 0.10}"
    elsif .j = 6
        .rgb$ = "{0.10, 0.65, 0.75}"
    elsif .j = 7
        .rgb$ = "{0.75, 0.20, 0.45}"
    elsif .j = 8
        .rgb$ = "{0.40, 0.40, 0.40}"
    endif
endproc

procedure drawFigure
    Erase all
    Line width: 1
    Solid line
    .step = max(1, floor(nFr / 900))
    Font size: 13
    Select inner viewport: 0.6, 7.7, 0.10, 0.60
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.72, "half", "##Spatial Dramaturgy — " + stratName$ + "##"
    Font size: 7
    Select inner viewport: 0.6, 7.7, 0.10, 0.60
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.42}"
    Text: 0.5, "centre", 0.18, "half", replace$(srcName$, "_", "\_ ", 0) + "   |   " + dSourceName$ + "   |   " + charName$ + "   |   seed " + string$(seed)

    # 1. dramaturgy curve
    Font size: 7
    Select inner viewport: 0.6, 7.7, 0.90, 1.80
    Axes: 0, dur, 0, 1
    Paint rectangle: "{0.98, 0.98, 0.99}", 0, dur, 0, 1
    Colour: "{0.10, 0.10, 0.10}"
    Line width: 2
    for zf from 1 + .step to nFr
        if (zf - 1) mod .step = 0
            zp = zf - .step
            Draw line: (zp - 0.5) * dtc, dd_'zp', (zf - 0.5) * dtc, dd_'zf'
        endif
    endfor
    Line width: 1
    Select inner viewport: 0.6, 7.7, 0.90, 1.80
    Axes: 0, dur, 0, 1
    Colour: "Black"
    Text top: "no", "##Dramaturgy D(t)## — " + dSourceName$ + "; peak " + fixed$(peakD, 2) + " at " + fixed$(peakT, 1) + " s"
    Select inner viewport: 0.6, 7.7, 0.90, 1.80
    Axes: 0, dur, 0, 1
    Draw inner box
    Marks left every: 1, 0.5, "yes", "yes", "no"
    @niceStep: dur, 8
    Marks bottom every: 1, niceStep.step, "no", "yes", "no"
    @railLabel: 0.90, 1.80, "D(t)"

    # 2. seven spatial lanes (the state used for rendering)
    .l0 = 2.10
    .lh = 0.36
    for zdim to 7
        .y0 = .l0 + (zdim - 1) * .lh
        .y1 = .y0 + .lh * 0.92
        Select inner viewport: 0.6, 7.7, .y0, .y1
        Axes: 0, dur, 0, 1
        Paint rectangle: "{0.98, 0.98, 0.99}", 0, dur, 0, 1
        @dimColour: zdim
        Colour: dimColour.rgb$
        Line width: 1.5
        for zf from 1 + .step to nFr
            if (zf - 1) mod .step = 0
                zp = zf - .step
                Draw line: (zp - 0.5) * dtc, st_'zdim'_'zp', (zf - 0.5) * dtc, st_'zdim'_'zf'
            endif
        endfor
        Line width: 1
        if zdim = 7 and nAg > 1
            Colour: "{0.30, 0.30, 0.30}"
            Dotted line
            for zf from 1 + .step to nFr
                if (zf - 1) mod .step = 0
                    zp = zf - .step
                    Draw line: (zp - 0.5) * dtc, (nActive_'zp' - 1) / max(1, nAg - 1), (zf - 0.5) * dtc, (nActive_'zf' - 1) / max(1, nAg - 1)
                endif
            endfor
            Solid line
        endif
        Font size: 6
        Select inner viewport: 0.6, 7.7, .y0, .y1
        Axes: 0, 1, 0, 1
        Colour: dimColour.rgb$
        .lab$ = "##" + dimName'zdim'$ + "##  " + replace$(map'zdim'$, "%", "\% ", 0)
        if zdim = 7 and nAg > 1
            .lab$ = .lab$ + "   (dotted: active agents 1-" + string$(nAg) + ")"
        endif
        Text: 0.005, "left", 0.8, "half", .lab$
        Select inner viewport: 0.6, 7.7, .y0, .y1
        Axes: 0, 1, 0, 1
        Colour: "Black"
        Draw inner box
        Font size: 7
    endfor
    Select inner viewport: 0.6, 7.7, .l0, .l0 + 7 * .lh
    Axes: 0, dur, 0, 1
    @niceStep: dur, 8
    Marks bottom every: 1, niceStep.step, "yes", "yes", "no"
    @railLabel: .l0, .l0 + 7 * .lh, "Spatial state (0-1)"
    Select inner viewport: 0.6, 7.7, .l0, .l0 + 7 * .lh
    Axes: 0, 1, 0, 1
    Text top: "no", "##Spatial state## — the seven dimensions as rendered (" + charName$ + ")"

    # 3. agent azimuth score
    .a0 = 5.15
    .a1 = 6.35
    Select inner viewport: 0.6, 7.7, .a0, .a1
    Axes: 0, dur, -180, 180
    Paint rectangle: "{0.98, 0.98, 0.99}", 0, dur, -180, 180
    Colour: "{0.85, 0.85, 0.88}"
    Draw line: 0, 0, dur, 0
    Dotted line
    Draw line: 0, 90, dur, 90
    Draw line: 0, -90, dur, -90
    Solid line
    Line width: 1.3
    for zj to nAg
        @agColour: zj
        Colour: agColour.rgb$
        for zf from 1 + .step to nFr
            if (zf - 1) mod .step = 0
                zp = zf - .step
                if agRel_'zj'_'zf' > 0.05 and abs(agAz_'zj'_'zf' - agAz_'zj'_'zp') < 180
                    Draw line: (zp - 0.5) * dtc, agAz_'zj'_'zp', (zf - 0.5) * dtc, agAz_'zj'_'zf'
                endif
            endif
        endfor
    endfor
    Line width: 1
    Select inner viewport: 0.6, 7.7, .a0, .a1
    Axes: 0, dur, -180, 180
    Colour: "Black"
    Text top: "no", "##Agent azimuths## (0 = front, +-90 = sides, +-180 = rear; agents drawn while released)"
    Select inner viewport: 0.6, 7.7, .a0, .a1
    Axes: 0, dur, -180, 180
    Draw inner box
    Marks left every: 1, 90, "yes", "yes", "no"
    @niceStep: dur, 8
    Marks bottom every: 1, niceStep.step, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    @railLabel: .a0, .a1, "Azimuth (deg)"

    # 4a. top-down field: speakers and trajectories (radius = 0.35 + 0.6 x distance)
    .f0 = 6.90
    .f1 = 9.30
    Select inner viewport: 0.6, 3.6, .f0, .f1
    Axes: -1.1, 1.1, -1.1, 1.1
    Paint rectangle: "{0.98, 0.98, 0.99}", -1.1, 1.1, -1.1, 1.1
    Colour: "{0.82, 0.82, 0.86}"
    Draw circle: 0, 0, 1
    Draw circle: 0, 0, 0.35
    if not ambi
        for zs to nCh
            Paint circle (mm): "{0.25, 0.25, 0.25}", sin(spkAz_'zs' * pi / 180), cos(spkAz_'zs' * pi / 180), 1.6
        endfor
    endif
    Paint circle (mm): "{0.25, 0.25, 0.25}", 0, 0, 1.0
    Line width: 1
    for zj to nAg
        for zf from 1 + .step to nFr
            if (zf - 1) mod .step = 0 and agRel_'zj'_'zf' > 0.05
                zp = zf - .step
                if abs(agAz_'zj'_'zf' - agAz_'zj'_'zp') < 90
                .ra = 0.35 + 0.6 * st_2_'zp'
                .rb = 0.35 + 0.6 * st_2_'zf'
                .u = zf / nFr
                Colour: "{" + fixed$(0.20 + 0.70 * .u, 3) + ", 0.40, " + fixed$(0.80 - 0.70 * .u, 3) + "}"
                Draw line: .ra * sin(agAz_'zj'_'zp' * pi / 180), .ra * cos(agAz_'zj'_'zp' * pi / 180), .rb * sin(agAz_'zj'_'zf' * pi / 180), .rb * cos(agAz_'zj'_'zf' * pi / 180)
                endif
            endif
        endfor
    endfor
    Select inner viewport: 0.6, 3.6, .f0, .f1
    Axes: -1.1, 1.1, -1.1, 1.1
    Colour: "Black"
    Text top: "no", "##Field from above## (front up; blue→orange = time)"
    Select inner viewport: 0.6, 3.6, .f0, .f1
    Axes: -1.1, 1.1, -1.1, 1.1
    Draw inner box

    # 4b. per-channel energy over time: MEASURED from the output (optional,
    # costs one channel copy and 120 RMS queries per channel) or, by default,
    # the rendering GAINS themselves (sum over agents of gain^2, each agent
    # weighted by release^2; independent of the agents' signal levels)
    .nW = 120
    Select inner viewport: 4.3, 7.7, .f0, .f1
    Axes: 0, dur, 0.5, nCh + 0.5
    .eMax = 1e-30
    if measureEnergy
        for zc to nCh
            selectObject: out
            .ch = Extract one channel: zc
            for zw to .nW
                .r = Get root-mean-square: (zw - 1) / .nW * dur, zw / .nW * dur
                chE_'zc'_'zw' = .r * .r
                .eMax = max(.eMax, chE_'zc'_'zw')
            endfor
            removeObject: .ch
        endfor
    else
        for zw to .nW
            zfr = max(1, min(nFr, round((zw - 0.5) / .nW * nFr)))
            for zc to nCh
                chE_'zc'_'zw' = 0
            endfor
            for zj to nAg
                .wj = agRel_'zj'_'zfr'
                selectObject: gains
                for zc to nCh
                    .g = Get value at sample number: (zj - 1) * nCh + zc, zfr
                    chE_'zc'_'zw' = chE_'zc'_'zw' + .wj * .wj * .g * .g
                endfor
            endfor
            for zc to nCh
                .eMax = max(.eMax, chE_'zc'_'zw')
            endfor
        endfor
    endif
    for zc to nCh
        for zw to .nW
            .lev = max(0, min(1, (10 * log10(max(chE_'zc'_'zw', 1e-30) / .eMax) + 40) / 40))
            .g = 1 - .lev
            Paint rectangle: "{" + fixed$(0.15 + 0.85 * .g, 3) + ", " + fixed$(0.25 + 0.75 * .g, 3) + ", " + fixed$(0.55 + 0.45 * .g, 3) + "}", (zw - 1) / .nW * dur, zw / .nW * dur, zc - 0.5, zc + 0.5
        endfor
    endfor
    Select inner viewport: 4.3, 7.7, .f0, .f1
    Axes: 0, dur, 0.5, nCh + 0.5
    Colour: "Black"
    .what$ = "##Routing gain map## (gain^2 x release^2)"
    if measureEnergy
        .what$ = "##Output energy (measured)##"
    endif
    if ambi
        Text top: "no", .what$ + " — rows: W Y Z X"
    else
        Text top: "no", .what$ + " — one row per speaker, 40 dB range"
    endif
    Select inner viewport: 4.3, 7.7, .f0, .f1
    Axes: 0, dur, 0.5, nCh + 0.5
    Draw inner box
    @niceStep: dur, 4
    Marks bottom every: 1, niceStep.step, "yes", "yes", "no"
    if nCh <= 16
        Marks left every: 1, 1, "yes", "yes", "no"
    endif
    Text bottom: "yes", "Time (s)"

    # summary
    .s0 = 9.85
    .s1 = 10.85
    Font size: 7
    Select inner viewport: 0.6, 7.7, .s0, .s1
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Text: 0.012, "left", 0.86, "half", "##Summary##"
    Font size: 6
    Select inner viewport: 0.6, 7.7, .s0, .s1
    Axes: 0, 1, 0, 1
    Colour: "{0.25, 0.25, 0.28}"
    Text: 0.012, "left", 0.64, "half", "Strategy " + stratName$ + ", character " + charName$ + "   |   agents up to " + string$(nAg) + " (" + fragMethodName$ + "), max active " + fixed$(maxActive, 1)
    Text: 0.012, "left", 0.46, "half", "Renderer: " + layoutName$
    .dl$ = "Distance: amplitude 1/(1+2d) + direct/diffuse blend; no propagation delay, air absorption or room model"
    if not ambi
        .dl$ = .dl$ + "; elevation shown as diffuseness only"
    endif
    Text: 0.012, "left", 0.28, "half", .dl$
    Text: 0.012, "left", 0.10, "half", "Peak dramaturgy " + fixed$(peakD, 2) + " at " + fixed$(peakT, 1) + " s   |   max spread " + fixed$(mx_1, 2) + ", max fragmentation " + fixed$(mx_7, 2) + "   |   seed " + string$(seed) + "   |   " + normNote$
    Select inner viewport: 0.6, 7.7, .s0, .s1
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 10
    Select outer viewport: 0, 8, 0, 10.95
endproc
