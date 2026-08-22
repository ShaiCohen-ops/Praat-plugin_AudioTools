# Changelog v0.5: visualization standardization only - unified typography, summary/full-page Picture framing; DSP/analysis unchanged.
# ============================================================
# Praat AudioTools - BFG_Pitch_Time_Modulation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   BFG-INSPIRED procedural control-field modulator for Praat Manipulation.
#   This is NOT a native/compatible emulation of Cycling '74 jit.bfg.
#
#   A deterministic 2-D procedural field N(x,y) is sampled along time and
#   channel trajectories and mapped to PSOLA pitch targets and, optionally,
#   to a shared DurationTier.
#
#   IMPORTANT INPUT SCOPE
#   ---------------------
#   Pitch modulation depends on Praat's Manipulation pitch analysis and is
#   therefore intended primarily for voiced speech, singing, and other
#   approximately monophonic pitched material. It is not a transparent
#   universal pitch shifter for polyphonic, noisy, or percussive sources.
#
#   Coordinate mapping
#     elapsed source time tau -> field X: x = tau * Field_rate_units_per_s
#     channel                 -> field Y: y = (ch-1)*Y_offset_per_channel
#
#   For periodic bases, Field_rate_units_per_s is also a cycle rate.
#   For noise/fractal bases it is a DOMAIN TRAVERSAL RATE, not a single Hz
#   modulation frequency. Fractal bases contain finer scales up to roughly:
#
#       detail_rate ~= field_rate * lacunarity^(octaves-1)
#
#   Pitch mapping
#       semitone deviation = Np(t)*Pitch_depth_semitones
#       pitch factor       = 2^(deviation/12)
#
#   Duration mapping
#       relative duration = 1 + Nt(t)*Time_depth_percent/100
#
#   Praat DurationTier values are relative DURATION factors, not playback
#   speed. Values >1 locally lengthen time; values <1 locally shorten it.
#
# BFG RELATION
# ------------
#   Cycling '74 jit.bfg evaluates a large library of procedural basis
#   functions and function graphs in arbitrary-dimensional coordinate fields.
#   The basis functions below are custom Praat implementations/analogues;
#   they are not asserted to be numerically identical to jit.bfg classes.
#
# v0.5 conceptual/DSP review
# --------------------------
#   - Reframed as BFG-inspired, not "native jit.bfg emulation".
#   - Explicitly scoped to PSOLA/trackable-F0 material.
#   - Field X uses ELAPSED TIME (t-tStart), so modulation is invariant to the
#     Sound object's absolute time origin.
#   - "Zoom speed" renamed conceptually to field traversal rate (units/s).
#   - Every preset now explicitly sets lacunarity as well as persistence.
#   - Misleading preset names (tape/turntable/granular/arpeggiator/doppler)
#     replaced by names that describe the actual PSOLA operation.
#   - Realization calibration centres EACH pitch-channel trajectory
#     independently, then uses one shared gain so relative depth is preserved.
#   - Shared time field is calibrated separately.
#   - DurationTier is generated ONCE and reused across all channels.
#   - Duration control-point density adapts to field detail rate.
#   - Calibrated DurationTier uses a trapezoidal zero-mean field, so its
#     modeled average relative duration is exactly 1 before edge/resynthesis
#     effects.
#   - Removed destructive trim-to-shortest-channel stage. Praat can combine
#     channels with different duration/time domains directly.
#   - No-voiced-point channels keep their original pitch tier instead of
#     replacing it with an empty tier.
#   - Manipulation analysis time step adapts to field detail rate, within a
#     practical 2..10 ms range.
#   - Pitch targets are bounded to 20 Hz .. 0.45*Fs with clipping QC.
#   - Visualization labels raw field map separately from calibrated channel
#     trajectories and includes the shared time-control trajectory.
#   - Attenuate-only peak ceiling retained.
#
# ============================================================

form BFG-Inspired Pitch and Duration Modulation v0.5
    comment Select a Sound object first

    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Subtle Vibrato
        option Organic Vibrato
        option Multiscale Pitch-Time Drift
        option Slow Value-Noise Drift
        option Stereo Chorus Detune
        option Drunken Choir
        option Fast Multiscale Pitch Shiver
        option Cellular Pitch Jumps
        option Chromatic Cellular Steps
        option Wide Pitch-Time Warp
        option Quantum Glitch
        option Slow Sine Pitch Sweep
        option Ridge Snap
        option Turbulent Warp
        option Sparse Pitch Excursions
        option Cell-Edge Detune
        option Checker Trill
        option Quasiperiodic Stereo Detune
        option Triangle Pitch-Time Warp
        option Hard Trill

    comment === BFG basis ===
    optionmenu Basis_type 1
        option Perlin fBm (smooth)
        option Ridged multifractal
        option Turbulence (billow)
        option Value noise
        option Sparse convolution
        option Voronoi cellular (stepped)
        option Cellular edges (F2-F1)
        option Checker (hard grid)
        option Sine LFO
        option Sine bank (3 partials)
        option Triangle LFO
        option Square LFO (trill)
    positive Field_rate_units_per_s 4.5
    natural Octaves 3
    positive Persistence 0.5
    positive Lacunarity 2.0
    integer Random_seed 12345

    comment === Depth ===
    real Pitch_depth_semitones 0.5
    real Quantize_grid_semitones 0
    real Time_depth_percent 0
    positive Time_rate_ratio 0.25
    real Y_offset_per_channel 1.5
    boolean Calibrate_realized_depth 1

    comment === PSOLA analysis ===
    positive Pitch_floor 75
    positive Pitch_ceiling 600

    comment === Output ===
    positive Peak_ceiling 0.95
    boolean Draw_visualization 1
    boolean Draw_bfg_map 1
    natural Map_columns 180
    natural Map_rows 48
    boolean Play_result 1
endform

# ============================================================
# Check Selection
# ============================================================
if numberOfSelected ("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalSoundID = selected ("Sound")
originalName$   = selected$ ("Sound")

selectObject: originalSoundID
nChan    = Get number of channels
tStart   = Get start time
tEnd     = Get end time
duration = Get total duration
sr       = Get sampling frequency

if duration < 0.05
    exitScript: "Sound is too short for PSOLA resynthesis (0.05 s minimum)."
endif

basisName$[1]  = "Perlin fBm (smooth)"
basisName$[2]  = "Ridged multifractal"
basisName$[3]  = "Turbulence (billow)"
basisName$[4]  = "Value noise"
basisName$[5]  = "Sparse convolution"
basisName$[6]  = "Voronoi cellular (stepped)"
basisName$[7]  = "Cellular edges (F2-F1)"
basisName$[8]  = "Checker (hard grid)"
basisName$[9]  = "Sine LFO"
basisName$[10] = "Sine bank (3 partials)"
basisName$[11] = "Triangle LFO"
basisName$[12] = "Square LFO (trill)"

# ============================================================
# Apply Presets
# Every preset explicitly sets the parameters that determine field shape and
# modulation behaviour (basis, field rate, octaves, persistence, lacunarity,
# pitch/time depth, time-rate ratio, quantization, and channel Y spacing).
# Random_seed and output/visualization options remain user-global by design.
# ============================================================
if preset = 2
    # gentle singer's vibrato, barely decorrelated
    basis_type = 1
    field_rate_units_per_s = 5.5
    octaves = 2
    persistence = 0.5
    lacunarity = 2.0
    pitch_depth_semitones = 0.30
    quantize_grid_semitones = 0
    time_depth_percent = 0
    time_rate_ratio = 0.25
    y_offset_per_channel = 0.7
    presetName$ = "Subtle Vibrato"
elsif preset = 3
    # irregular, breathing vibrato - the fBm octaves do the work
    basis_type = 1
    field_rate_units_per_s = 4.5
    octaves = 3
    persistence = 0.5
    lacunarity = 2.0
    pitch_depth_semitones = 0.80
    quantize_grid_semitones = 0
    time_depth_percent = 0
    time_rate_ratio = 0.25
    y_offset_per_channel = 1.5
    presetName$ = "Organic Vibrato"
elsif preset = 4
    # slow wow under fast flutter, plus a little time warp
    basis_type = 1
    field_rate_units_per_s = 3.0
    octaves = 4
    persistence = 0.65
    lacunarity = 2.0
    pitch_depth_semitones = 0.50
    quantize_grid_semitones = 0
    time_depth_percent = 5
    time_rate_ratio = 0.15
    y_offset_per_channel = 1.5
    presetName$ = "Multiscale Pitch-Time Drift"
elsif preset = 5
    # worn tape: very slow, wide-lattice drift
    basis_type = 4
    field_rate_units_per_s = 0.25
    octaves = 2
    persistence = 0.5
    lacunarity = 2.0
    pitch_depth_semitones = 0.70
    quantize_grid_semitones = 0
    time_depth_percent = 3
    time_rate_ratio = 0.5
    y_offset_per_channel = 2.0
    presetName$ = "Slow Value-Noise Drift"
elsif preset = 6
    # near-static detune, channels far apart on the Y axis
    basis_type = 1
    field_rate_units_per_s = 0.9
    octaves = 2
    persistence = 0.5
    lacunarity = 2.0
    pitch_depth_semitones = 0.25
    quantize_grid_semitones = 0
    time_depth_percent = 0
    time_rate_ratio = 0.25
    y_offset_per_channel = 4.0
    presetName$ = "Stereo Chorus Detune"
elsif preset = 7
    # wide, slow, heavily decorrelated - unison that cannot agree
    basis_type = 1
    field_rate_units_per_s = 1.6
    octaves = 3
    persistence = 0.55
    lacunarity = 2.0
    pitch_depth_semitones = 2.50
    quantize_grid_semitones = 0
    time_depth_percent = 0
    time_rate_ratio = 0.25
    y_offset_per_channel = 6.0
    presetName$ = "Drunken Choir"
elsif preset = 8
    # fast, shallow multiscale pitch motion within the practical PSOLA band
    basis_type = 1
    field_rate_units_per_s = 10
    octaves = 4
    persistence = 0.65
    lacunarity = 2.0
    pitch_depth_semitones = 0.35
    quantize_grid_semitones = 0
    time_depth_percent = 0
    time_rate_ratio = 0.25
    y_offset_per_channel = 2.5
    presetName$ = "Fast Multiscale Pitch Shiver"
elsif preset = 9
    # dense cellular jumps, one new pitch every ~45 ms
    basis_type = 6
    field_rate_units_per_s = 22
    octaves = 3
    persistence = 0.5
    lacunarity = 2.0
    pitch_depth_semitones = 7.0
    quantize_grid_semitones = 0
    time_depth_percent = 0
    time_rate_ratio = 0.25
    y_offset_per_channel = 3.0
    presetName$ = "Cellular Pitch Jumps"
elsif preset = 10
    # cellular steps snapped to the chromatic grid
    basis_type = 6
    field_rate_units_per_s = 6
    octaves = 3
    persistence = 0.5
    lacunarity = 2.0
    pitch_depth_semitones = 12.0
    quantize_grid_semitones = 1
    time_depth_percent = 0
    time_rate_ratio = 0.25
    y_offset_per_channel = 1.5
    presetName$ = "Chromatic Cellular Steps"
elsif preset = 11
    # heavy simultaneous pitch and time warp
    basis_type = 4
    field_rate_units_per_s = 1.2
    octaves = 2
    persistence = 0.5
    lacunarity = 2.0
    pitch_depth_semitones = 3.0
    quantize_grid_semitones = 0
    time_depth_percent = 35
    time_rate_ratio = 0.6
    y_offset_per_channel = 1.5
    presetName$ = "Wide Pitch-Time Warp"
elsif preset = 12
    # whole-tone steps at granular rate with a violent time warp
    basis_type = 6
    field_rate_units_per_s = 30
    octaves = 3
    persistence = 0.5
    lacunarity = 2.0
    pitch_depth_semitones = 4.0
    quantize_grid_semitones = 2
    time_depth_percent = 55
    time_rate_ratio = 1.0
    y_offset_per_channel = 3.5
    presetName$ = "Quantum Glitch"
elsif preset = 13
    # one slow sine sweep, channels a quarter cycle apart
    basis_type = 9
    field_rate_units_per_s = 0.35
    octaves = 3
    persistence = 0.5
    lacunarity = 2.0
    pitch_depth_semitones = 6.0
    quantize_grid_semitones = 0
    time_depth_percent = 0
    time_rate_ratio = 0.25
    y_offset_per_channel = 2.0
    presetName$ = "Slow Sine Pitch Sweep"
elsif preset = 14
    # ridged noise: long flat valleys broken by sharp upward spikes
    basis_type = 2
    field_rate_units_per_s = 5.0
    octaves = 4
    persistence = 0.55
    lacunarity = 2.0
    pitch_depth_semitones = 2.00
    quantize_grid_semitones = 0
    time_depth_percent = 0
    time_rate_ratio = 0.25
    y_offset_per_channel = 2.0
    presetName$ = "Ridge Snap"
elsif preset = 15
    # turbulence on both pitch and duration - unstable, seasick
    basis_type = 3
    field_rate_units_per_s = 4.0
    octaves = 4
    persistence = 0.6
    lacunarity = 2.0
    pitch_depth_semitones = 1.20
    quantize_grid_semitones = 0
    time_depth_percent = 12
    time_rate_ratio = 0.3
    y_offset_per_channel = 2.0
    presetName$ = "Turbulent Warp"
elsif preset = 16
    # isolated impulse kernels: mostly unmodulated, occasional events
    basis_type = 5
    field_rate_units_per_s = 3.0
    octaves = 3
    persistence = 0.5
    lacunarity = 2.0
    pitch_depth_semitones = 5.00
    quantize_grid_semitones = 1
    time_depth_percent = 0
    time_rate_ratio = 0.25
    y_offset_per_channel = 2.5
    presetName$ = "Sparse Pitch Excursions"
elsif preset = 17
    # cell-edge ridges: flat inside a cell, brief dips at boundaries
    basis_type = 7
    field_rate_units_per_s = 12
    octaves = 3
    persistence = 0.5
    lacunarity = 2.0
    pitch_depth_semitones = 1.50
    quantize_grid_semitones = 0
    time_depth_percent = 0
    time_rate_ratio = 0.25
    y_offset_per_channel = 3.0
    presetName$ = "Cell-Edge Detune"
elsif preset = 18
    # hard two-state alternation; Y offset 1.0 inverts the channels
    basis_type = 8
    field_rate_units_per_s = 9
    octaves = 3
    persistence = 0.5
    lacunarity = 2.0
    pitch_depth_semitones = 3.00
    quantize_grid_semitones = 1
    time_depth_percent = 0
    time_rate_ratio = 0.25
    y_offset_per_channel = 1.0
    presetName$ = "Checker Trill"
elsif preset = 19
    # three incommensurate partials - a vibrato that never repeats
    basis_type = 10
    field_rate_units_per_s = 2.2
    octaves = 3
    persistence = 0.5
    lacunarity = 2.0
    pitch_depth_semitones = 0.60
    quantize_grid_semitones = 0
    time_depth_percent = 0
    time_rate_ratio = 0.25
    y_offset_per_channel = 3.0
    presetName$ = "Quasiperiodic Stereo Detune"
elsif preset = 20
    # linear ramps on pitch and duration together
    basis_type = 11
    field_rate_units_per_s = 0.6
    octaves = 3
    persistence = 0.5
    lacunarity = 2.0
    pitch_depth_semitones = 8.00
    quantize_grid_semitones = 0
    time_depth_percent = 20
    time_rate_ratio = 1.0
    y_offset_per_channel = 1.5
    presetName$ = "Triangle Pitch-Time Warp"
elsif preset = 21
    # square wave snapped to one semitone: a real trill
    basis_type = 12
    field_rate_units_per_s = 7
    octaves = 3
    persistence = 0.5
    lacunarity = 2.0
    pitch_depth_semitones = 1.00
    quantize_grid_semitones = 1
    time_depth_percent = 0
    time_rate_ratio = 0.25
    y_offset_per_channel = 1.5
    presetName$ = "Hard Trill"
else
    presetName$ = "Custom"
endif

basisLabel$ = basisName$[basis_type]

# ============================================================
# Parameter Validation
# ============================================================
if pitch_floor >= pitch_ceiling
    exitScript: "Pitch floor must be below pitch ceiling."
endif
if pitch_ceiling >= 0.45*sr
    exitScript: "Pitch ceiling must be below 0.45 times the Sound sampling rate."
endif
if octaves > 8
    octaves = 8
endif
if lacunarity < 1
    exitScript: "Lacunarity must be at least 1."
endif
if persistence <= 0 or persistence > 1.5
    exitScript: "Persistence must be > 0 and <= 1.5."
endif
if abs (pitch_depth_semitones) > 48
    pitch_depth_semitones = 48 * ((pitch_depth_semitones > 0) - (pitch_depth_semitones < 0))
endif
if abs (time_depth_percent) > 90
    time_depth_percent = 90 * ((time_depth_percent > 0) - (time_depth_percent < 0))
endif
if quantize_grid_semitones < 0
    quantize_grid_semitones = 0
endif
if peak_ceiling > 1
    peak_ceiling = 1
endif
if map_columns > 600
    map_columns = 600
endif
if map_rows > 180
    map_rows = 180
endif

# Estimate the finest intended field scale. For irregular noise this is a
# characteristic domain-crossing rate, not a strict spectral cutoff.
fieldDetailRate = field_rate_units_per_s
if basis_type = 1 or basis_type = 2 or basis_type = 3
    fieldDetailRate =
        ... field_rate_units_per_s*lacunarity^(octaves-1)
elsif basis_type = 10
    fieldDetailRate =
        ... field_rate_units_per_s*2.718282
endif

timeFieldDetailRate = fieldDetailRate*time_rate_ratio

# Adapt Manipulation analysis time step to the requested field detail while
# keeping computation practical.
if fieldDetailRate > 0
    analysisTimeStep =
        ... max(0.002,min(0.010,1/(8*fieldDetailRate)))
else
    analysisTimeStep = 0.010
endif

pitchControlSamplesPerDetail =
    ... 1/(analysisTimeStep*max(1e-9,fieldDetailRate))

controlBandWarning = 0
if pitchControlSamplesPerDetail < 4
    controlBandWarning = 1
endif

# deterministic offset injected into the hash so Random_seed affects the
# stochastic/custom-noise bases without using Praat's global RNG.
nGain = 1
nOffset# = zero#(nChan)
tGain = 1
tOffset = 0
hashSeed = random_seed*0.6180339887

# Shared duration field: deliberately on a separate Y trajectory that cannot
# coincide with any channel plane for ordinary positive/negative Y offsets.
timePlaneY =
    ... (nChan+3)*max(1,abs(y_offset_per_channel))+17.375

# Pitch targets outside this range are not meaningful/robust for this engine.
minSafePitch = 20
maxSafePitch = 0.45*sr
pitchTargetClipCount = 0

clearinfo
writeInfoLine: "=============================================="
appendInfoLine: "  BFG-INSPIRED PITCH AND DURATION MODULATION v0.5"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Source: ", originalName$, " (", fixed$ (duration, 2), " s, ",
   ... nChan, " ch, ", sr, " Hz)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Basis:  ", basisLabel$
appendInfoLine: "Field rate: ", fixed$ (field_rate_units_per_s, 3), " units/s   Depth: ",
   ... fixed$ (pitch_depth_semitones, 3), " st"
if quantize_grid_semitones > 0
    appendInfoLine: "Grid:   ", fixed$ (quantize_grid_semitones, 2), " st"
endif
appendInfoLine: "Field detail rate estimate: ", fixed$ (fieldDetailRate, 3), " units/s"
appendInfoLine: "Manipulation analysis step: ", fixed$ (1000*analysisTimeStep, 3), " ms"
appendInfoLine: "Approx. control samples/detail: ", fixed$ (pitchControlSamplesPerDetail, 2)
if controlBandWarning
    appendInfoLine: "WARNING: requested field detail is faster than robust PSOLA target sampling."
endif
appendInfoLine: "Input scope: PSOLA; best for voiced/monophonic trackable-F0 material"
appendInfoLine: ""

# ============================================================
# STEP 1: REALIZED PITCH-FIELD CALIBRATION
# ============================================================
appendInfoLine: "STEP 1: Calibrating realized pitch trajectories..."

# Calibrate exactly the channel Y trajectories the audio will use.
# Each channel receives its own mean offset; one common gain is derived from
# the largest centred excursion across all channels.
if calibrate_realized_depth
    normalizationScanCapped = 0
    nScanWanted =
        ... max(1200,ceiling(duration*8*max(1,fieldDetailRate))+1)
    nScan = min(12000,nScanWanted)
    if nScan < nScanWanted
        normalizationScanCapped = 1
    endif

    for ch from 1 to nChan
        ys = (ch-1)*y_offset_per_channel
        sumN = 0

        for i from 1 to nScan
            tau =
                ... ((i-1)/(nScan-1))*duration
            @bfgRaw: tau*field_rate_units_per_s, ys
            sumN = sumN+bfgRaw.result
        endfor

        nOffset#[ch] = sumN/nScan
    endfor

    peakN = 0
    for ch from 1 to nChan
        ys = (ch-1)*y_offset_per_channel

        for i from 1 to nScan
            tau =
                ... ((i-1)/(nScan-1))*duration
            @bfgRaw: tau*field_rate_units_per_s, ys
            centred = bfgRaw.result-nOffset#[ch]
            peakN = max(peakN,abs(centred))
        endfor
    endfor

    if peakN > 1e-9
        nGain = 1/peakN
    endif
else
    nScan = 0
    normalizationScanCapped = 0
endif

appendInfoLine: "  shared pitch-field gain ", fixed$(nGain,5)
for ch from 1 to nChan
    appendInfoLine: "  channel ", ch,
        ... " offset ", fixed$(nOffset#[ch],5)
endfor
if normalizationScanCapped
    appendInfoLine: "  NOTE: calibration scan capped at 12000 samples."
endif

# ============================================================
# STEP 2: SHARED DURATION FIELD + PER-CHANNEL PSOLA MODULATION
# ============================================================
appendInfoLine: ""
appendInfoLine: "STEP 2: Building shared DurationTier and modulating pitch tiers..."

# ---------------------------------------------------------------------------
# Shared DurationTier
# ---------------------------------------------------------------------------
durationTierID = 0
expectedDuration = duration
nDurPts = 0
durationControlCapped = 0

if time_depth_percent <> 0
    nDurWanted =
        ... max(400,ceiling(duration*8*max(1,timeFieldDetailRate)))
    nDurPts = min(6000,nDurWanted)
    if nDurPts < nDurWanted
        durationControlCapped = 1
    endif

    rawTime# = zero#(nDurPts+1)
    normTime# = zero#(nDurPts+1)
    relTime# = zero#(nDurPts+1)

    for k from 0 to nDurPts
        tau = (k/nDurPts)*duration
        @bfgRaw:
            ... tau*field_rate_units_per_s*time_rate_ratio,
            ... timePlaneY
        rawTime#[k+1] = bfgRaw.result
    endfor

    if calibrate_realized_depth
        # Exact trapezoidal mean of the piecewise-linear control represented
        # by these control points.
        trapSum =
            ... 0.5*rawTime#[1]+0.5*rawTime#[nDurPts+1]
        for k from 1 to nDurPts-1
            trapSum = trapSum+rawTime#[k+1]
        endfor
        tOffset = trapSum/nDurPts

        peakT = 0
        for k from 0 to nDurPts
            peakT =
                ... max(peakT,abs(rawTime#[k+1]-tOffset))
        endfor
        if peakT > 1e-9
            tGain = 1/peakT
        endif
    endif

    durationTierID =
        ... Create DurationTier: "bfg_shared_duration",tStart,tEnd

    for k from 0 to nDurPts
        tk = tStart+(k/nDurPts)*duration
        normalizedTime =
            ... (rawTime#[k+1]-tOffset)*tGain
        normalizedTime =
            ... max(-1,min(1,normalizedTime))
        normTime#[k+1] = normalizedTime

        rel =
            ... 1+normalizedTime*time_depth_percent/100
        rel = max(0.1,min(10,rel))
        relTime#[k+1] = rel
        Add point: tk,rel
    endfor

    # Integral of the piecewise-linear DurationTier.
    relTrap =
        ... 0.5*relTime#[1]+0.5*relTime#[nDurPts+1]
    for k from 1 to nDurPts-1
        relTrap = relTrap+relTime#[k+1]
    endfor
    expectedDuration =
        ... duration*(relTrap/nDurPts)

    appendInfoLine: "  Time field offset/gain: ",
        ... fixed$(tOffset,5), " / ", fixed$(tGain,5)
    appendInfoLine: "  Duration control points: ", nDurPts+1,
        ... "  expected duration ", fixed$(expectedDuration,5), " s"
    if durationControlCapped
        appendInfoLine: "  NOTE: duration control grid capped at 6001 points."
    endif
else
    appendInfoLine: "  Duration modulation: off"
endif

totalPoints = 0
nStored     = 0
minFac      = 1
maxFac      = 1

for ch to nChan
    selectObject: originalSoundID
    if nChan > 1
        work = Extract one channel: ch
    else
        work = Copy: "bfgwork"
    endif

    yCh = (ch - 1) * y_offset_per_channel

    selectObject: work
    manip = To Manipulation: analysisTimeStep, pitch_floor, pitch_ceiling

    selectObject: manip
    srcTier = Extract pitch tier

    selectObject: srcTier
    nPts = Get number of points
    for i from 1 to nPts
        pT[i] = Get time from index: i
        pF[i] = Get value at index: i
    endfor

    minFacCh = 1
    maxFacCh = 1
    if nPts > 0
        minFacCh = 1e30
        maxFacCh = -1e30
    endif

    newTier = 0

    if nPts > 0
        newTier = Create PitchTier: "bfgtier",tStart,tEnd

        for i from 1 to nPts
            tau = pT[i]-tStart
            @bfgPitch:
                ... tau*field_rate_units_per_s,yCh,ch

            semi =
                ... bfgPitch.result*pitch_depth_semitones

            if quantize_grid_semitones > 0
                semi =
                    ... round(semi/quantize_grid_semitones)*
                    ... quantize_grid_semitones
            endif

            pFactor = 2^(semi/12)

            if pFactor < minFacCh
                minFacCh = pFactor
            endif
            if pFactor > maxFacCh
                maxFacCh = pFactor
            endif

            requestedF = pF[i]*pFactor
            newF =
                ... max(minSafePitch,
                ... min(maxSafePitch,requestedF))

            if abs(newF-requestedF) > 1e-12
                pitchTargetClipCount =
                    ... pitchTargetClipCount+1
            endif

            Add point: pT[i],newF

            if ch = 1
                plotT[i] = pT[i]
                plotOrig[i] = pF[i]
                plotMod[i] = newF
            endif
        endfor

        selectObject: manip,newTier
        Replace pitch tier
    endif

    if ch = 1
        nStored = nPts
        minFac = minFacCh
        maxFac = maxFacCh
    endif
    totalPoints = totalPoints+nPts

    # One shared DurationTier is reused for every channel.
    if durationTierID <> 0
        selectObject: manip,durationTierID
        Replace duration tier
    endif

    selectObject: manip
    out[ch] = Get resynthesis (overlap-add)
    Rename: "bfgch" + string$ (ch)

    removeObject: work,manip,srcTier
    if newTier <> 0
        removeObject: newTier
    endif

    appendInfoLine: "  Channel ", ch, ": y = ", fixed$ (yCh, 2),
       ... "  points = ", nPts,
       ... "  P factor = ", fixed$ (minFacCh, 4), " .. ", fixed$ (maxFacCh, 4)
    if nPts = 0
        appendInfoLine: "    WARNING: no pitch targets detected - original pitch tier retained."
    endif
endfor

if durationTierID <> 0
    removeObject: durationTierID
endif

# ============================================================
# STEP 3: RECOMBINE AND GAIN STAGE
# ============================================================
appendInfoLine: ""
appendInfoLine: "STEP 3: Recombining and gain staging..."

# Praat can combine Sounds with different duration/time domains; do not
# destroy tails by trimming channels to the shortest resynthesis.

if nChan = 1
    resultID = out[1]
else
    selectObject: out[1]
    for ch from 2 to nChan
        plusObject: out[ch]
    endfor
    resultID = Combine to stereo
    for ch to nChan
        removeObject: out[ch]
    endfor
endif

selectObject: resultID
Rename: originalName$ + "_bfg_" + replace$ (presetName$, " ", "", 0)
Shift times to: "start time", tStart

rawPeak = Get absolute extremum: 0, 0, "None"
gainApplied = 1
if rawPeak > peak_ceiling and rawPeak > 0
    gainApplied = peak_ceiling / rawPeak
    Formula: "self * gainApplied"
endif
resultDur  = Get total duration
resultPeak = Get absolute extremum: 0, 0, "None"

appendInfoLine: "  Duration: ", fixed$(resultDur,3),
    ... " s (input ", fixed$(duration,3),
    ... " s; tier model ", fixed$(expectedDuration,3), " s)"
appendInfoLine: "  Pitch targets clipped to safe range: ",
    ... pitchTargetClipCount
appendInfoLine: "  Peak before ceiling: ", fixed$ (rawPeak, 4)
if gainApplied < 1
    appendInfoLine: "  Ceiling applied: x", fixed$ (gainApplied, 4),
       ... " -> ", fixed$ (resultPeak, 4)
else
    appendInfoLine: "  Ceiling not needed (attenuate-only stage)"
endif

# ============================================================
# STEP 4: VISUALIZATION
# v0.4: compact one-screen canvas, about 6.7 inches tall.
# Basis map full width; N(t) and pitch tier side by side;
# output waveform full width; three-column summary.
# ============================================================
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "STEP 4: Creating Visualization..."

    nPlot = 400
    yLast = (nChan - 1) * y_offset_per_channel
    for i from 1 to nPlot
        tp = tStart + ((i - 1) / (nPlot - 1)) * duration
        plotX[i] = tp
        @bfgPitch: (tp-tStart)*field_rate_units_per_s, 0, 1
        nA[i] = bfgPitch.result
        @bfgPitch: (tp-tStart)*field_rate_units_per_s, yLast, nChan
        nB[i] = bfgPitch.result

        if time_depth_percent <> 0
            @bfgTime:
                ... (tp-tStart)*field_rate_units_per_s*time_rate_ratio,
                ... timePlaneY
            nTime[i] = bfgTime.result
        else
            nTime[i] = 0
        endif
    endfor

    @niceStep: duration
    tTick = niceStep.result
    @niceStep: duration * 2
    tTickHalf = niceStep.result

    Erase all
    Font size: 7
    Line width: 1
    Solid line
    Colour: "Black"

    # === TITLE ===
    Select outer viewport: 0, 8, 0, 0.5
    Select inner viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.72, "half",
       ... "##BFG-Inspired Pitch and Duration Modulation v0.5## | " + replace$ (originalName$, "_", "-", 0)
    Font size: 7
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", 0.26, "half", presetName$ + " | " + basisLabel$ +
       ... " | field rate " + fixed$ (field_rate_units_per_s, 2) + " u/s | depth " +
       ... fixed$ (pitch_depth_semitones, 2) + " st"
    Colour: "Black"

    # === 2D BASIS MAP (full width) ===
    mapTop = 0.55
    mapBot = 2.35
    if draw_bfg_map
        mapYmin = -0.6
        mapYmax = yLast + 0.6
        dxMap = duration / map_columns
        dyMap = (mapYmax - mapYmin) / map_rows

        bfgMatrix = Create simple Matrix: "bfgmap", map_rows, map_columns, "0"
        for iy from 1 to map_rows
            yv = mapYmin + (iy - 0.5) * dyMap
            for ix from 1 to map_columns
                xv = tStart + (ix - 0.5) * dxMap
                @bfgMap:
                    ... (xv-tStart)*field_rate_units_per_s,yv
                Set value: iy,ix,bfgMap.result
            endfor
        endfor

        Select outer viewport: 0, 8, mapTop, mapBot
        Select inner viewport: 0.6, 7.7, mapTop + 0.22, mapBot - 0.05
        selectObject: bfgMatrix
        Paint image: 0, 0, 0, 0, -1, 1
        removeObject: bfgMatrix

        Select outer viewport: 0, 8, mapTop, mapBot
        Select inner viewport: 0.6, 7.7, mapTop + 0.22, mapBot - 0.05
        Axes: tStart, tEnd, mapYmin, mapYmax

        Line width: 2
        for ch from 1 to nChan
            ych = (ch - 1) * y_offset_per_channel
            @chanColour: ch
            Colour: chanColour.result$
            Draw line: tStart, ych, tEnd, ych
        endfor
        Line width: 1
        Font size: 6
        for ch from 1 to nChan
            ych = (ch - 1) * y_offset_per_channel
            Paint rectangle: "{1.0, 1.0, 1.0}", tStart + 0.012 * duration,
               ... tStart + 0.068 * duration, ych + 0.05, ych + 0.27
            @chanColour: ch
            Colour: chanColour.result$
            Text: tStart + 0.020 * duration, "left", ych + 0.08, "bottom", "ch " + string$ (ch)
        endfor

        Colour: "Black"
        Line width: 0.5
        Draw inner box
        Line width: 1
        Font size: 6
        Marks bottom every: 1, tTick, "yes", "yes", "no"
        Marks left every: 1, 1, "yes", "yes", "no"
        Font size: 7
        Text top: "no", "Raw 2D procedural field - channel tracks below are realization-calibrated"
    else
        mapBot = mapTop
    endif

    rowTop = mapBot + 0.20
    rowBot = rowTop + 1.55

    # === N(t) CONTROL SIGNAL (left half) ===
    Select outer viewport: 0, 4, rowTop, rowBot
    Select inner viewport: 0.6, 3.85, rowTop + 0.22, rowBot - 0.30
    Axes: tStart, tEnd, -1.10, 1.10

    Paint rectangle: "{0.96, 0.96, 0.97}", tStart, tEnd, -1.10, 1.10
    Colour: "{0.80, 0.80, 0.80}"
    Draw line: tStart, 0, tEnd, 0
    Line width: 1.5
    @chanColour: 1
    Colour: chanColour.result$
    for i from 2 to nPlot
        Draw line: plotX[i - 1], nA[i - 1], plotX[i], nA[i]
    endfor
    if nChan > 1
        @chanColour: nChan
        Colour: chanColour.result$
        for i from 2 to nPlot
            Draw line: plotX[i-1],nB[i-1],plotX[i],nB[i]
        endfor
    endif

    if time_depth_percent <> 0
        Colour: "{0.20, 0.62, 0.36}"
        Dotted line
        for i from 2 to nPlot
            Draw line:
                ... plotX[i-1],nTime[i-1],
                ... plotX[i],nTime[i]
        endfor
        Solid line
    endif

    Line width: 0.5
    Colour: "Black"
    Draw inner box
    Line width: 1
    Font size: 6
    Marks bottom every: 1, tTickHalf, "yes", "yes", "no"
    Marks left every: 1, 0.5, "yes", "yes", "no"
    Font size: 7
    if quantize_grid_semitones > 0
        Text top: "no", "Calibrated pitch field Np(t); green dotted = shared duration field Nt(t).  +-1 = " + fixed$ (pitch_depth_semitones, 2) +
           ... " st on a " + fixed$ (quantize_grid_semitones, 2) + " st grid"
    else
        Text top: "no", "Calibrated pitch field Np(t); green dotted = shared duration field Nt(t).  +-1 = " + fixed$ (pitch_depth_semitones, 2) + " st"
    endif

    # === PITCH TIER, CHANNEL 1 (right half) ===
    Select outer viewport: 4, 8, rowTop, rowBot
    Select inner viewport: 4.45, 7.7, rowTop + 0.22, rowBot - 0.30

    if nStored < 2
        Axes: 0, 1, 0, 1
        Font size: 7
        Text: 0.5, "centre", 0.5, "half", "no voiced pitch points"
        Line width: 0.5
        Draw inner box
        Line width: 1
    else
        fLo = 1e30
        fHi = -1e30
        for i from 1 to nStored
            if plotOrig[i] < fLo
                fLo = plotOrig[i]
            endif
            if plotMod[i] < fLo
                fLo = plotMod[i]
            endif
            if plotOrig[i] > fHi
                fHi = plotOrig[i]
            endif
            if plotMod[i] > fHi
                fHi = plotMod[i]
            endif
        endfor
        pad = 0.06 * (fHi - fLo) + 1
        fLo = fLo - pad
        fHi = fHi + pad
        @niceStep: fHi - fLo
        markStep = niceStep.result

        stepI = 1
        if nStored > 1200
            stepI = ceiling (nStored / 1200)
        endif
        nSeg = floor ((nStored - 1) / stepI)

        Axes: tStart, tEnd, fLo, fHi
        Paint rectangle: "{0.96, 0.96, 0.97}", tStart, tEnd, fLo, fHi

        Colour: "{0.55, 0.55, 0.55}"
        Line width: 1
        for j from 1 to nSeg
            ia = 1 + (j - 1) * stepI
            ib = 1 + j * stepI
            if plotT[ib] - plotT[ia] < 0.05
                Draw line: plotT[ia], plotOrig[ia], plotT[ib], plotOrig[ib]
            endif
        endfor
        Colour: "{0.85, 0.15, 0.15}"
        Line width: 1.5
        for j from 1 to nSeg
            ia = 1 + (j - 1) * stepI
            ib = 1 + j * stepI
            if plotT[ib] - plotT[ia] < 0.05
                Draw line: plotT[ia], plotMod[ia], plotT[ib], plotMod[ib]
            endif
        endfor

        Line width: 0.5
        Colour: "Black"
        Draw inner box
        Line width: 1
        Font size: 6
        Marks bottom every: 1, tTickHalf, "yes", "yes", "no"
        Marks left every: 1, markStep, "yes", "yes", "no"
    endif
    Font size: 7
    Text top: "no", "Pitch tier ch 1, F0 (Hz) vs time: grey = original, red = modulated"

    # === OUTPUT WAVEFORM (full width) ===
    wavTop = rowBot + 0.10
    wavBot = wavTop + 1.05
    Select outer viewport: 0, 8, wavTop, wavBot
    Select inner viewport: 0.6, 7.7, wavTop + 0.22, wavBot - 0.25

    selectObject: resultID
    wMax = Get maximum: 0, 0, "None"
    wMin = Get minimum: 0, 0, "None"
    wRange = max (abs (wMax), abs (wMin))
    if wRange <= 0
        wRange = 1
    endif
    wRange = wRange * 1.08
    Colour: "{0.30, 0.45, 0.70}"
    Draw: 0, 0, -wRange, wRange, "no", "Curve"

    # Draw stacks multichannel sounds vertically, so only the time axis is
    # meaningful here - no left marks; the peak is reported in the caption.
    @niceStep: resultDur
    Axes: tStart, tStart + resultDur, -wRange, wRange
    Line width: 0.5
    Colour: "Black"
    Draw inner box
    Line width: 1
    Font size: 6
    Marks bottom every: 1, niceStep.result, "yes", "yes", "no"
    Font size: 7
    Text top: "no", "Resynthesised output vs time (s), overlap-add - peak " + fixed$ (resultPeak, 3)

    # === SUMMARY PANEL (three columns) ===
    sumTop = wavBot + 0.10
    sumBot = sumTop + 1.00
    Select outer viewport: 0, 8, sumTop, sumBot
    Select inner viewport: 0.6, 7.7, sumTop + 0.03, sumBot - 0.03
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.87, "half", "##Basis##"
    Text: 0.36, "left", 0.87, "half", "##Modulation##"
    Text: 0.70, "left", 0.87, "half", "##Output##"

    Font size: 6
    Text: 0.02, "left", 0.65, "half", basisLabel$
    Text: 0.02, "left", 0.45, "half", "field " + fixed$ (field_rate_units_per_s, 2) +
       ... " u/s   oct " + string$ (octaves) + "   pers " + fixed$ (persistence, 2) +
       ... "   lac " + fixed$ (lacunarity, 2)
    Text: 0.02, "left", 0.25, "half", "seed " + string$ (random_seed) +
       ... "   Y offset " + fixed$ (y_offset_per_channel, 2)
    Text: 0.02, "left", 0.08, "half", "cal ch1 offset " + fixed$(nOffset#[1],3) +
       ... "  shared gain " + fixed$(nGain,3)

    Text: 0.36, "left", 0.65, "half", "depth " +
       ... fixed$ (pitch_depth_semitones, 2) + " st   grid " +
       ... fixed$ (quantize_grid_semitones, 2) + " st"
    Text: 0.36, "left", 0.45, "half", "P factor ch1 " +
       ... fixed$ (minFac, 4) + " .. " + fixed$ (maxFac, 4)
    Text: 0.36, "left", 0.25, "half", "time depth " +
       ... fixed$(time_depth_percent,1) + " pct  rate ratio " +
       ... fixed$(time_rate_ratio,2)
    Text: 0.36, "left", 0.08, "half", "points " + string$(totalPoints) +
       ... "  step " + fixed$(1000*analysisTimeStep,1) + " ms  PSOLA " + fixed$ (pitch_floor, 0) + "-" + fixed$ (pitch_ceiling, 0) + " Hz"

    Text: 0.70, "left", 0.65, "half", "preset: " + presetName$
    Text: 0.70, "left", 0.45, "half", "duration " + fixed$(resultDur,3) +
       ... " s | tier model " + fixed$(expectedDuration,3) + " s"
    Text: 0.70, "left", 0.25, "half", "peak " + fixed$ (resultPeak, 4) +
       ... "   ceiling x" + fixed$ (gainApplied, 3)
    Text: 0.70, "left", 0.08, "half", string$ (nChan) + " ch   " +
       ... string$ (sr) + " Hz"

    Line width: 0.5
    Draw inner box
    Line width: 1
    Font size: 10

    appendInfoLine: "  Visualization complete (canvas ", fixed$ (sumBot, 2), " inches)"

    pageHeight = sumBot
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# ============================================================
# CLEANUP AND FINAL SELECTION
# ============================================================
appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE"
appendInfoLine: "=============================================="
appendInfoLine: ""
selectObject: resultID
finalName$ = selected$ ("Sound")
appendInfoLine: "Created: ", finalName$, " (", fixed$ (resultDur, 2), " s)"

# === Play ===
if play_result
    selectObject: resultID
    Play
endif

selectObject: resultID

# ============================================================
# BASIS FUNCTION GENERATOR
# ============================================================

# ---- round tick step for an axis range --------------------------------------
procedure niceStep: .range
    .raw = .range / 8
    if .raw <= 0
        .raw = 1
    endif
    .mag = 10 ^ floor (log10 (.raw))
    .n = .raw / .mag
    if .n < 1.5
        .result = .mag
    elsif .n < 3
        .result = 2 * .mag
    elsif .n < 7
        .result = 5 * .mag
    else
        .result = 10 * .mag
    endif
endproc

# ---- channel colour lookup --------------------------------------------------
procedure chanColour: .ch
    if .ch = 1
        .result$ = "{0.85, 0.55, 0.10}"
    elsif .ch = 2
        .result$ = "{0.20, 0.45, 0.85}"
    elsif .ch = 3
        .result$ = "{0.35, 0.70, 0.40}"
    elsif .ch = 4
        .result$ = "{0.75, 0.30, 0.65}"
    elsif .ch = 5
        .result$ = "{0.20, 0.70, 0.70}"
    elsif .ch = 6
        .result$ = "{0.80, 0.35, 0.30}"
    elsif .ch = 7
        .result$ = "{0.50, 0.45, 0.75}"
    else
        .result$ = "{0.45, 0.45, 0.45}"
    endif
endproc

# ---- raw basis value, before centring / scaling -----------------------------
procedure bfgRaw: .x, .y
    if basis_type = 1
        @fbm: .x, .y
        .result = fbm.result
    elsif basis_type = 2
        @ridged: .x, .y
        .result = ridged.result
    elsif basis_type = 3
        @turbulence: .x, .y
        .result = turbulence.result
    elsif basis_type = 4
        @vnoise: .x, .y
        .result = vnoise.result
    elsif basis_type = 5
        @sparse: .x, .y
        .result = sparse.result
    elsif basis_type = 6
        @cellular: .x, .y
        .result = cellular.result
    elsif basis_type = 7
        @cellEdge: .x, .y
        .result = cellEdge.result
    elsif basis_type = 8
        @checker: .x, .y
        .result = checker.result
    elsif basis_type = 9
        .result = sin (2 * pi * .x + .y * pi / 2)
    elsif basis_type = 10
        @sineBank: .x, .y
        .result = sineBank.result
    elsif basis_type = 11
        @triangle: .x, .y
        .result = triangle.result
    else
        @square: .x, .y
        .result = square.result
    endif
endproc

# ---- Raw field for the 2-D map; no clip-realization centring ----------------
procedure bfgMap: .x,.y
    @bfgRaw: .x,.y
    .result = max(-1,min(1,bfgRaw.result))
endproc

# ---- Np(x,y,ch) on actual pitch-channel trajectories ------------------------
procedure bfgPitch: .x,.y,.ch
    @bfgRaw: .x,.y
    .result =
        ... (bfgRaw.result-nOffset#[.ch])*nGain
    .result = max(-1,min(1,.result))
endproc

# ---- Nt(x,y) on the shared duration plane ----------------------------------
procedure bfgTime: .x, .y
    @bfgRaw: .x, .y
    .result = (bfgRaw.result - tOffset) * tGain
    if .result > 1
        .result = 1
    elsif .result < -1
        .result = -1
    endif
endproc

# ---- deterministic hash, returns [0, 1) -------------------------------------
procedure hash2: .x, .y
    .h = sin (.x * 127.1 + .y * 311.7 + hashSeed) * 43758.5453123
    .result = .h - floor (.h)
endproc

# ---- gradient dot product for Perlin ----------------------------------------
procedure gradDot: .ix, .iy, .dx, .dy
    @hash2: .ix, .iy
    .ang = hash2.result * 2 * pi
    .result = cos (.ang) * .dx + sin (.ang) * .dy
endproc

# ---- 2D Perlin gradient noise, roughly [-0.707, +0.707] ---------------------
procedure perlin2: .x, .y
    .x0 = floor (.x)
    .y0 = floor (.y)
    .fx = .x - .x0
    .fy = .y - .y0
    .ux = .fx * .fx * .fx * (.fx * (.fx * 6 - 15) + 10)
    .uy = .fy * .fy * .fy * (.fy * (.fy * 6 - 15) + 10)
    @gradDot: .x0,     .y0,     .fx,     .fy
    .n00 = gradDot.result
    @gradDot: .x0 + 1, .y0,     .fx - 1, .fy
    .n10 = gradDot.result
    @gradDot: .x0,     .y0 + 1, .fx,     .fy - 1
    .n01 = gradDot.result
    @gradDot: .x0 + 1, .y0 + 1, .fx - 1, .fy - 1
    .n11 = gradDot.result
    .a = .n00 + .ux * (.n10 - .n00)
    .b = .n01 + .ux * (.n11 - .n01)
    .result = .a + .uy * (.b - .a)
endproc

# ---- fractal Brownian motion over Perlin ------------------------------------
procedure fbm: .x, .y
    .sum  = 0
    .amp  = 1
    .frq  = 1
    .norm = 0
    for .o from 1 to octaves
        @perlin2: .x * .frq, .y * .frq
        .sum  = .sum + perlin2.result * .amp
        .norm = .norm + .amp
        .amp  = .amp * persistence
        .frq  = .frq * lacunarity
    endfor
    .result = (.sum / .norm) * 1.41421356
endproc

# ---- 2D value noise, quintic interpolation, [-1, +1] ------------------------
procedure vnoise: .x, .y
    .x0 = floor (.x)
    .y0 = floor (.y)
    .fx = .x - .x0
    .fy = .y - .y0
    .ux = .fx * .fx * .fx * (.fx * (.fx * 6 - 15) + 10)
    .uy = .fy * .fy * .fy * (.fy * (.fy * 6 - 15) + 10)
    @hash2: .x0,     .y0
    .v00 = hash2.result * 2 - 1
    @hash2: .x0 + 1, .y0
    .v10 = hash2.result * 2 - 1
    @hash2: .x0,     .y0 + 1
    .v01 = hash2.result * 2 - 1
    @hash2: .x0 + 1, .y0 + 1
    .v11 = hash2.result * 2 - 1
    .a = .v00 + .ux * (.v10 - .v00)
    .b = .v01 + .ux * (.v11 - .v01)
    .result = .a + .uy * (.b - .a)
endproc

# ---- Worley / Voronoi cellular noise: piecewise constant, [-1, +1] ----------
procedure cellular: .x, .y
    .xi = floor (.x)
    .yi = floor (.y)
    .best = 1e30
    .val  = 0
    for .dx from -1 to 1
        for .dy from -1 to 1
            @hash2: .xi + .dx + 13.53, .yi + .dy + 7.21
            .jx = hash2.result
            @hash2: .xi + .dx + 41.77, .yi + .dy + 23.13
            .jy = hash2.result
            .px = .xi + .dx + .jx
            .py = .yi + .dy + .jy
            .d = (.px - .x) ^ 2 + (.py - .y) ^ 2
            if .d < .best
                .best = .d
                @hash2: .px * 3.71, .py * 5.37
                .val = hash2.result * 2 - 1
            endif
        endfor
    endfor
    .result = .val
endproc

# ---- ridged multifractal: flat valleys, sharp upward ridges -----------------
procedure ridged: .x, .y
    .sum  = 0
    .amp  = 1
    .frq  = 1
    .norm = 0
    for .o from 1 to octaves
        @perlin2: .x * .frq, .y * .frq
        .r = 1 - abs (perlin2.result) * 1.41421356
        if .r < 0
            .r = 0
        endif
        .sum  = .sum + .r * .r * .amp
        .norm = .norm + .amp
        .amp  = .amp * persistence
        .frq  = .frq * lacunarity
    endfor
    .result = 2 * (.sum / .norm) - 1
endproc

# ---- turbulence / billow: puffy, rectified fBm ------------------------------
procedure turbulence: .x, .y
    .sum  = 0
    .amp  = 1
    .frq  = 1
    .norm = 0
    for .o from 1 to octaves
        @perlin2: .x * .frq, .y * .frq
        .sum  = .sum + abs (perlin2.result) * 1.41421356 * .amp
        .norm = .norm + .amp
        .amp  = .amp * persistence
        .frq  = .frq * lacunarity
    endfor
    .result = 2 * (.sum / .norm) - 1
endproc

# ---- sparse convolution: isolated signed impulse kernels --------------------
procedure sparse: .x, .y
    .xi  = floor (.x)
    .yi  = floor (.y)
    .acc = 0
    for .dx from -1 to 1
        for .dy from -1 to 1
            @hash2: .xi + .dx + 3.11, .yi + .dy + 8.47
            .h1 = hash2.result
            @hash2: .xi + .dx + 19.73, .yi + .dy + 2.33
            .h2 = hash2.result
            @hash2: .xi + .dx + 55.31, .yi + .dy + 61.97
            .h3 = hash2.result
            .px = .xi + .dx + .h1
            .py = .yi + .dy + .h2
            .d = sqrt ((.px - .x) ^ 2 + (.py - .y) ^ 2)
            if .d < 0.85
                .k = 0.5 + 0.5 * cos (pi * .d / 0.85)
                if .h3 < 0.5
                    .acc = .acc - .k
                else
                    .acc = .acc + .k
                endif
            endif
        endfor
    endfor
    .result = .acc
endproc

# ---- cellular edges: F2 - F1, flat inside cells, dips at boundaries ---------
procedure cellEdge: .x, .y
    .xi = floor (.x)
    .yi = floor (.y)
    .f1 = 1e30
    .f2 = 1e30
    for .dx from -1 to 1
        for .dy from -1 to 1
            @hash2: .xi + .dx + 13.53, .yi + .dy + 7.21
            .jx = hash2.result
            @hash2: .xi + .dx + 41.77, .yi + .dy + 23.13
            .jy = hash2.result
            .d = sqrt ((.xi + .dx + .jx - .x) ^ 2 + (.yi + .dy + .jy - .y) ^ 2)
            if .d < .f1
                .f2 = .f1
                .f1 = .d
            elsif .d < .f2
                .f2 = .d
            endif
        endfor
    endfor
    .e = (.f2 - .f1) * 2
    if .e > 1
        .e = 1
    endif
    .result = 2 * .e - 1
endproc

# ---- checker: hard two-state grid, Y offset 1.0 inverts a channel -----------
procedure checker: .x, .y
    .c = floor (.x) + floor (.y)
    if .c - 2 * floor (.c / 2) = 0
        .result = 1
    else
        .result = -1
    endif
endproc

# ---- sine bank: three incommensurate partials, never repeats ----------------
procedure sineBank: .x, .y
    .result = sin (2 * pi * .x + .y * pi / 2) * 0.55
       ... + sin (2 * pi * 1.618034 * .x + .y * 0.77) * 0.30
       ... + sin (2 * pi * 2.718282 * .x + .y * 1.31) * 0.15
endproc

# ---- triangle LFO: linear ramps up and down ---------------------------------
procedure triangle: .x, .y
    .p = .x + .y * 0.25 + 0.25
    .f = .p - floor (.p)
    .result = 4 * abs (.f - 0.5) - 1
endproc

# ---- square LFO: hard two-state trill ---------------------------------------
procedure square: .x, .y
    .s = sin (2 * pi * .x + .y * pi / 2)
    if .s >= 0
        .result = 1
    else
        .result = -1
    endif
endproc
