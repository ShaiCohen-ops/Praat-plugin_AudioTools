# ============================================================
# Praat AudioTools - Chaotic Granular Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.3.1 reviewed (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Deterministic nonlinear granular synthesis.
#
#   A Logistic map, Henon map, or Lorenz system generates the control states
#   that determine each grain's:
#       inter-onset interval / local density
#       duration
#       frequency
#       amplitude
#       stereo pan
#
#   Grains use a Hann envelope and a phase referenced to grain age.
#   A grain that crosses an internal synthesis-chunk boundary is evaluated
#   continuously on both sides of that boundary; it is NOT truncated and no
#   crossfade is required between chunks.
#
# Signal model:
#     nonlinear state -> grain parameter map -> Hann grains
#     -> exact chunk continuation -> layer sum -> optional normalization
#
# v1.3.1: panel II rendered EMPTY in the Picture window while exporting
#   correctly to PNG. Cause: it was the only panel drawn entirely from
#   hairline strokes and micro-dots — Line width 0.3 with segments 0.0012
#   wide out of a 0.6 range for the bifurcation, and Paint circle (mm) at
#   0.07-0.09 mm radius for the attractors. All of those are well under one
#   device pixel on screen and get dropped by the on-screen renderer, while
#   at 300 dpi they are 2-5 px and look fine. Panels I, III and IV are area
#   fills, which always occupy at least one pixel, so only panel II vanished.
#   Now: Line width 1 throughout, bifurcation points drawn as short vertical
#   ticks with real extent, attractor dots at 0.20-0.38 mm, and Gabor cells
#   in panel I given a floor on width and height for the same reason.
#   LESSON: verifying a figure only at 300 dpi does not verify what the user
#   sees. Any mark specified in mm or in tiny world-coordinate deltas must be
#   checked at screen resolution too.
#
# v1.3 reviewed (visualization only; the signal path is unchanged):
#   - Figure re-cast along the two lineages this instrument actually sits in:
#     Gabor 1946 for the grain, Lorenz 1963 / Henon 1976 / May 1976 for the
#     control law. It now runs quantum -> law -> statistics -> sound.
#       I   THE INFORMATION DIAGRAM  every rendered grain drawn as its own
#           Gabor cell on a LINEAR frequency axis (Gabor's own plane): width
#           = grain duration, height = 1.5/duration, the Hann equivalent
#           noise bandwidth. Because that product is constant, every cell has
#           the same area whatever the grain's length — Gabor's quantum, and
#           the reason plane occupancy depends on grain COUNT, not duration.
#           A log axis would collapse the high cells to hairlines and hide
#           exactly the point the panel makes.
#       II  THE DYNAMICAL LAW  logistic bifurcation diagram with the
#           operating r marked, or the Henon / Lorenz attractor drawn from a
#           long re-run with the states that actually drove this synthesis
#           marked on top. The stored orbit holds one state per layer-1
#           grain — of order a hundred — which on its own looks like a smear
#           rather than an attractor.
#       III THE INVARIANT MEASURE  the realized states as bars, with the
#           law's invariant density from a 60k-iterate run drawn over them,
#           and the grain-frequency histogram beneath. The density's shape is
#           the law's; the audible frequency distribution inherits it.
#       IV  THE SOUND ITSELF  measured spectrogram.
#   - Lyapunov exponent reported, computed from a long run rather than from
#     the realized orbit: ~100 states is far too few, and gave 0.50 for Henon
#     against a converged 0.419. The exponent is a property of the attractor,
#     so the long run is the right source. For Lorenz it is the exponent of
#     the system AS INTEGRATED (Euler, dt 0.005, ~0.95) rather than of the
#     ideal ODE (~0.906); the integrator is named in the label.
#   - Panels I-III marked "control field", panel IV "measured", with a note
#     strip stating that cell height is the Hann ENBW and not the Gabor
#     uncertainty minimum.
#
# v1.2 reviewed:
#   - Chaos now controls grain timing, duration, frequency, amplitude and pan.
#     The previous version used random grain times/durations and constant
#     amplitudes, with chaos controlling essentially frequency only.
#   - Removed silent max-30-grains-per-chunk dropping. Excessive workloads now
#     produce an explicit guard instead of changing the requested texture.
#   - Grains are no longer truncated at chunk boundaries.
#   - Removed Concatenate-with-overlap from the synthesis timeline. Because
#     crossing grains are evaluated with a shared age/phase/envelope, ordinary
#     Concatenate preserves the requested duration and schedule exactly.
#   - Logistic map uses r=3.97 with burn-in; randomization changes initial
#     state rather than silently choosing a different dynamical law per layer.
#   - Standard Henon parameters a=1.4, b=0.3 with burn-in; removed hard state
#     clamping, which changes the dynamical system.
#   - Standard Lorenz parameters sigma=10, rho=28, beta=8/3 with dt=0.005,
#     burn-in and internal substeps; removed one-Euler-step-per-grain transient.
#   - Added reproducible Random_seed (0 = unpredictable).
#   - Added sample-rate and Nyquist protection.
#   - Added explicit grain-duration and frequency-span controls.
#   - Energy compensation uses expected overlap and 1/sqrt(number of layers).
#   - Stereo Wide is now chaos-controlled equal-power grain panning; removed
#     complementary EQ, injected random noise and post-hoc Haas processing.
#   - One optional final/common normalization only.
#   - Visualization uses the ACTUAL rendered grain schedule and nonlinear
#     trajectory, plus a measured spectrogram with model grain guides.
# ============================================================

form Chaotic Granular Synthesis v1.2
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Logistic Sparse
        option Henon Texture
        option Lorenz Atmospheric

    comment === Texture ===
    positive Duration_s 10
    integer Sample_rate_Hz 44100
    positive Base_frequency_Hz 120
    positive Grain_density_grains_per_s 8
    integer Number_of_layers 3
    positive Min_grain_duration_ms 60
    positive Max_grain_duration_ms 220
    positive Frequency_span_octaves 2.5

    comment === Nonlinear system ===
    optionmenu Synthesis_mode 1
        option Logistic Map
        option Henon Map
        option Lorenz System
    boolean Randomize_initial_state 1
    integer Random_seed 0

    comment === Output ===
    optionmenu Spatial_mode 1
        option Mono
        option Stereo Wide
    real Edge_fade_s 0.05
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_after 1
endform

# ---------------------------------------------------------------------------
# 0. PRESETS
# ---------------------------------------------------------------------------
preset_name$ = "Custom"

if preset = 2
    preset_name$ = "Logistic Sparse"
    duration_s = 10
    sample_rate_Hz = 44100
    base_frequency_Hz = 120
    grain_density_grains_per_s = 7
    number_of_layers = 3
    min_grain_duration_ms = 55
    max_grain_duration_ms = 180
    frequency_span_octaves = 2.5
    synthesis_mode = 1
    spatial_mode = 1
    edge_fade_s = 0.05

elsif preset = 3
    preset_name$ = "Henon Texture"
    duration_s = 12
    sample_rate_Hz = 44100
    base_frequency_Hz = 100
    grain_density_grains_per_s = 8
    number_of_layers = 4
    min_grain_duration_ms = 70
    max_grain_duration_ms = 240
    frequency_span_octaves = 3.0
    synthesis_mode = 2
    spatial_mode = 2
    edge_fade_s = 0.05

elsif preset = 4
    preset_name$ = "Lorenz Atmospheric"
    duration_s = 15
    sample_rate_Hz = 44100
    base_frequency_Hz = 80
    grain_density_grains_per_s = 6
    number_of_layers = 3
    min_grain_duration_ms = 110
    max_grain_duration_ms = 360
    frequency_span_octaves = 3.5
    synthesis_mode = 3
    spatial_mode = 2
    edge_fade_s = 0.08
endif

# ---------------------------------------------------------------------------
# 1. LABELS / VALIDATION
# ---------------------------------------------------------------------------
if synthesis_mode = 1
    mode$ = "Logistic Map"
elsif synthesis_mode = 2
    mode$ = "Henon Map"
else
    mode$ = "Lorenz System"
endif

if spatial_mode = 1
    spatial$ = "Mono"
else
    spatial$ = "Stereo Wide"
endif

if duration_s <= 0
    exitScript: "Duration must be greater than zero."
endif
if sample_rate_Hz < 8000 or sample_rate_Hz > 192000
    exitScript: "Sample rate must be between 8000 and 192000 Hz."
endif
if base_frequency_Hz <= 0
    exitScript: "Base frequency must be greater than zero."
endif
if grain_density_grains_per_s <= 0
    exitScript: "Grain density must be greater than zero."
endif
if grain_density_grains_per_s > 150
    exitScript: "Grain density is limited to 150 grains/s/layer to keep Praat responsive."
endif
if number_of_layers < 1 or number_of_layers > 8
    exitScript: "Number of layers must be between 1 and 8."
endif
if min_grain_duration_ms <= 0
    exitScript: "Minimum grain duration must be greater than zero."
endif
if max_grain_duration_ms < min_grain_duration_ms
    exitScript: "Maximum grain duration must be >= minimum grain duration."
endif
if max_grain_duration_ms > 2000
    exitScript: "Maximum grain duration is limited to 2000 ms."
endif
if frequency_span_octaves <= 0 or frequency_span_octaves > 8
    exitScript: "Frequency span must be > 0 and <= 8 octaves."
endif
if random_seed < 0
    exitScript: "Random seed must be 0 or a positive integer."
endif
if edge_fade_s < 0
    exitScript: "Edge fade cannot be negative."
endif

twoPi = 2 * pi
safeTop = 0.45 * sample_rate_Hz
minAudible = 20
chunk_duration = min(1.0, duration_s)
num_chunks = ceiling(duration_s / chunk_duration)

minGrainDur = min_grain_duration_ms / 1000
maxGrainDur = max_grain_duration_ms / 1000
meanGrainDur = 0.5 * (minGrainDur + maxGrainDur)

# Workload guard: the density map can rise to 1.45 x the nominal density.
estimatedMaxGrains = ceiling(1.55 * duration_s * grain_density_grains_per_s * number_of_layers)
if estimatedMaxGrains > 6000
    exitScript: "This setting can exceed 6000 grains. Reduce duration, density or layers."
endif

# Frequency map:
#   f = base * 2^[layerOffset + span*(mFreq-0.5)]
# with a small octave offset between layers.
layerOctaveStep = 0.18
maxLayerOffset = layerOctaveStep * (number_of_layers - 1)
maxRatio = 2 ^ (0.5 * frequency_span_octaves + maxLayerOffset)
maxSafeBase = safeTop / maxRatio
baseWasAdjusted = 0

if base_frequency_Hz > maxSafeBase
    base_frequency_Hz = maxSafeBase
    baseWasAdjusted = 1
endif
if base_frequency_Hz <= 0
    exitScript: "Frequency span/layer settings leave no safe carrier range at this sample rate."
endif

uid$ = string$(randomInteger(10000, 99999))

seedWasFixed = 0
if randomize_initial_state
    if random_seed > 0
        random_initializeWithSeedUnsafelyButPredictably (random_seed)
        seedWasFixed = 1
        seedLabel$ = "seed " + string$(random_seed)
    else
        seedLabel$ = "seed random"
    endif
else
    seedLabel$ = "deterministic initial states"
endif

# ---------------------------------------------------------------------------
# 2. INFO / MIX CANVAS
# ---------------------------------------------------------------------------
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  CHAOTIC GRANULAR SYNTHESIS v1.2"
writeInfoLine: "=============================================="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "System: ", mode$
appendInfoLine: "Duration: ", fixed$(duration_s, 2), " s"
appendInfoLine: "Layers: ", number_of_layers
appendInfoLine: "Nominal density: ", fixed$(grain_density_grains_per_s, 2), " grains/s/layer"
appendInfoLine: "Grain duration: ", fixed$(minGrainDur*1000,0), "-", fixed$(maxGrainDur*1000,0), " ms"
appendInfoLine: "Frequency span: ", fixed$(frequency_span_octaves,2), " octaves"
appendInfoLine: "Spatial: ", spatial$
appendInfoLine: "Randomness: ", seedLabel$
if baseWasAdjusted
    appendInfoLine: "Base frequency reduced to ", fixed$(base_frequency_Hz,2), " Hz for Nyquist safety."
endif
appendInfoLine: ""

if spatial_mode = 1
    Create Sound from formula: "cgs_mix_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"
    mixID = selected("Sound")
else
    Create Sound from formula: "cgs_mix_left_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"
    mixLeftID = selected("Sound")
    Create Sound from formula: "cgs_mix_right_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"
    mixRightID = selected("Sound")
endif

# ---------------------------------------------------------------------------
# 3. GLOBAL MEASUREMENT STORAGE
# ---------------------------------------------------------------------------
total_grains_all = 0
chaos_point_count = 0
max_chaos_points = 700

freqMinRealized = safeTop
freqMaxRealized = minAudible
durSum = 0
ampMinRealized = 1e9
ampMaxRealized = 0
densityMinRealized = 1e9
densityMaxRealized = 0
panMinRealized = 1
panMaxRealized = 0
lowFreqCorrections = 0
highFreqCorrections = 0
maxTermsInChunk = 0

# Energy compensation: expected random-phase overlap per layer and across layers.
expectedOverlap = grain_density_grains_per_s * meanGrainDur
if expectedOverlap < 1
    expectedOverlap = 1
endif
baseGrainAmp = 0.52 / sqrt(number_of_layers * expectedOverlap)

# ---------------------------------------------------------------------------
# 4. PROCESS EACH LAYER
# ---------------------------------------------------------------------------
for layer from 1 to number_of_layers
    appendInfoLine: "Layer ", layer, "/", number_of_layers, "..."

    # ----- Initialize one dynamical law, with layer-specific initial state -----
    if synthesis_mode = 1
        logisticR = 3.97
        if randomize_initial_state
            chaos_x = randomUniform(0.11, 0.89)
        else
            chaos_x = 0.12 + 0.72 * layer / (number_of_layers + 1)
        endif
        burnIn = 250
        for burn to burnIn
            chaos_x = logisticR * chaos_x * (1 - chaos_x)
        endfor

    elsif synthesis_mode = 2
        henonA = 1.4
        henonB = 0.3
        if randomize_initial_state
            chaos_x = randomUniform(-0.10, 0.10)
            chaos_y = randomUniform(-0.10, 0.10)
        else
            chaos_x = 0.015 * layer
            chaos_y = -0.010 * layer
        endif
        burnIn = 600
        for burn to burnIn
            new_x = 1 - henonA * chaos_x * chaos_x + chaos_y
            new_y = henonB * chaos_x
            chaos_x = new_x
            chaos_y = new_y
        endfor

    else
        lorenzSigma = 10
        lorenzRho = 28
        lorenzBeta = 8 / 3
        lorenzDt = 0.005
        lorenzSubsteps = 8

        if randomize_initial_state
            chaos_x = randomUniform(-0.20, 0.20)
            chaos_y = randomUniform(-0.20, 0.20)
            chaos_z = randomUniform(0.05, 0.25)
        else
            chaos_x = 0.10 + 0.01 * layer
            chaos_y = 0.02 * layer
            chaos_z = 0.10
        endif

        burnIn = 4000
        for burn to burnIn
            dx = lorenzSigma * (chaos_y - chaos_x)
            dy = chaos_x * (lorenzRho - chaos_z) - chaos_y
            dz = chaos_x * chaos_y - lorenzBeta * chaos_z
            chaos_x = chaos_x + lorenzDt * dx
            chaos_y = chaos_y + lorenzDt * dy
            chaos_z = chaos_z + lorenzDt * dz
        endfor
    endif

    # ----- Generate the ACTUAL chaos-controlled grain schedule -----
    total_grains = 0
    eventTime = 0
    scheduleDone = 0
    maxLayerGrains = ceiling(1.55 * duration_s * grain_density_grains_per_s) + 20

    while scheduleDone = 0
        # Five bounded control values:
        # mFreq, mDur, mAmp, mDensity, mPan all in [0,1].

        if synthesis_mode = 1
            previousX = chaos_x

            chaos_x = logisticR * chaos_x * (1 - chaos_x)
            mFreq = chaos_x
            returnX = previousX
            returnY = chaos_x

            chaos_x = logisticR * chaos_x * (1 - chaos_x)
            mDur = chaos_x

            chaos_x = logisticR * chaos_x * (1 - chaos_x)
            mAmp = chaos_x

            chaos_x = logisticR * chaos_x * (1 - chaos_x)
            mDensity = chaos_x

            chaos_x = logisticR * chaos_x * (1 - chaos_x)
            mPan = chaos_x

            trajX = returnX
            trajY = returnY

        elsif synthesis_mode = 2
            # State 1 -> frequency/duration and trajectory point.
            new_x = 1 - henonA * chaos_x * chaos_x + chaos_y
            new_y = henonB * chaos_x
            chaos_x = new_x
            chaos_y = new_y
            if abs(chaos_x) > 5 or abs(chaos_y) > 5
                exitScript: "Henon trajectory escaped; synthesis stopped rather than clamping the map."
            endif

            trajX = chaos_x
            trajY = chaos_y
            mFreq = max(0, min(1, (chaos_x + 1.5) / 3.0))
            mDur = max(0, min(1, (chaos_y + 0.45) / 0.90))

            # State 2 -> amplitude/density.
            new_x = 1 - henonA * chaos_x * chaos_x + chaos_y
            new_y = henonB * chaos_x
            chaos_x = new_x
            chaos_y = new_y
            mAmp = max(0, min(1, (chaos_x + 1.5) / 3.0))
            mDensity = max(0, min(1, (chaos_y + 0.45) / 0.90))

            # State 3 -> pan.
            new_x = 1 - henonA * chaos_x * chaos_x + chaos_y
            new_y = henonB * chaos_x
            chaos_x = new_x
            chaos_y = new_y
            mPan = max(0, min(1, (chaos_x + 1.5) / 3.0))

        else
            # Advance the Lorenz system several small Euler steps before using
            # the state, so grain-to-grain controls sample the attractor rather
            # than a near-identical one-step sequence.
            for sub to lorenzSubsteps
                dx = lorenzSigma * (chaos_y - chaos_x)
                dy = chaos_x * (lorenzRho - chaos_z) - chaos_y
                dz = chaos_x * chaos_y - lorenzBeta * chaos_z
                chaos_x = chaos_x + lorenzDt * dx
                chaos_y = chaos_y + lorenzDt * dy
                chaos_z = chaos_z + lorenzDt * dz
            endfor

            trajX = chaos_x
            trajY = chaos_y
            mFreq = 1 / (1 + exp(-chaos_x / 8))
            mDur = 1 / (1 + exp(-chaos_y / 10))
            mAmp = 1 / (1 + exp(-(chaos_z - 25) / 10))

            for sub to lorenzSubsteps
                dx = lorenzSigma * (chaos_y - chaos_x)
                dy = chaos_x * (lorenzRho - chaos_z) - chaos_y
                dz = chaos_x * chaos_y - lorenzBeta * chaos_z
                chaos_x = chaos_x + lorenzDt * dx
                chaos_y = chaos_y + lorenzDt * dy
                chaos_z = chaos_z + lorenzDt * dz
            endfor

            mDensity = 1 / (1 + exp(-chaos_x / 8))
            mPan = 1 / (1 + exp(-chaos_y / 10))
        endif

        localDensity = grain_density_grains_per_s * (0.55 + 0.90 * mDensity)
        densityMinRealized = min(densityMinRealized, localDensity)
        densityMaxRealized = max(densityMaxRealized, localDensity)
        interval = 1 / localDensity

        if total_grains = 0
            nextTime = 0.5 * interval
        else
            nextTime = eventTime + interval
        endif

        if nextTime >= duration_s
            scheduleDone = 1
        elsif total_grains >= maxLayerGrains
            exitScript: "Internal grain schedule exceeded its safety bound. Reduce density or duration."
        else
            total_grains = total_grains + 1
            eventTime = nextTime

            grain_time[total_grains] = eventTime
            grain_dur[total_grains] = minGrainDur + (maxGrainDur - minGrainDur) * mDur

            if grain_time[total_grains] + grain_dur[total_grains] > duration_s
                grain_dur[total_grains] = duration_s - grain_time[total_grains]
            endif

            layerOffset = layerOctaveStep * (layer - 1)
            grain_freq[total_grains] = base_frequency_Hz * 2 ^ (layerOffset + frequency_span_octaves * (mFreq - 0.5))

            if grain_freq[total_grains] < minAudible
                grain_freq[total_grains] = minAudible
                lowFreqCorrections = lowFreqCorrections + 1
            endif
            if grain_freq[total_grains] > safeTop
                grain_freq[total_grains] = safeTop
                highFreqCorrections = highFreqCorrections + 1
            endif

            grain_amp[total_grains] = baseGrainAmp * (0.45 + 0.55 * mAmp)
            grain_pan[total_grains] = mPan
            grain_phase[total_grains] = twoPi * mPan

            # Store all ACTUALLY RENDERED grains for visualization/QC.
            total_grains_all = total_grains_all + 1
            viz_time[total_grains_all] = grain_time[total_grains]
            viz_dur[total_grains_all] = grain_dur[total_grains]
            viz_freq[total_grains_all] = grain_freq[total_grains]
            viz_amp[total_grains_all] = grain_amp[total_grains]
            viz_pan[total_grains_all] = grain_pan[total_grains]
            viz_layer[total_grains_all] = layer

            freqMinRealized = min(freqMinRealized, grain_freq[total_grains])
            freqMaxRealized = max(freqMaxRealized, grain_freq[total_grains])
            durSum = durSum + grain_dur[total_grains]
            ampMinRealized = min(ampMinRealized, grain_amp[total_grains])
            ampMaxRealized = max(ampMaxRealized, grain_amp[total_grains])
            panMinRealized = min(panMinRealized, grain_pan[total_grains])
            panMaxRealized = max(panMaxRealized, grain_pan[total_grains])

            if layer = 1 and chaos_point_count < max_chaos_points
                chaos_point_count = chaos_point_count + 1
                chaos_traj_x[chaos_point_count] = trajX
                chaos_traj_y[chaos_point_count] = trajY
            endif
        endif
    endwhile

    appendInfoLine: "  scheduled grains: ", total_grains

    # ----- Render chronological chunks WITHOUT truncating crossing grains -----
    if spatial_mode = 1
        for chunk to num_chunks
            chunkStart = (chunk - 1) * chunk_duration
            chunkEnd = min(chunk * chunk_duration, duration_s)
            actualChunkDur = chunkEnd - chunkStart
            chunkFormula$ = "0"
            termsInChunk = 0

            for grain to total_grains
                grainStart = grain_time[grain]
                grainEnd = grainStart + grain_dur[grain]

                if grainEnd > chunkStart and grainStart < chunkEnd
                    termsInChunk = termsInChunk + 1
                    if termsInChunk > 180
                        exitScript: "More than 180 overlapping grain terms in one synthesis chunk. Reduce density or grain duration."
                    endif

                    localStart = grainStart - chunkStart
                    localClipStart = max(0, localStart)
                    localClipEnd = min(actualChunkDur, localStart + grain_dur[grain])

                    sLocalStart$ = fixed$(localStart, 9)
                    sClipStart$ = fixed$(localClipStart, 9)
                    sClipEnd$ = fixed$(localClipEnd, 9)
                    sDur$ = fixed$(grain_dur[grain], 9)
                    sFreq$ = fixed$(grain_freq[grain], 5)
                    sAmp$ = fixed$(grain_amp[grain], 7)
                    sPhase$ = fixed$(grain_phase[grain], 7)

                    wave$ = "sin(2*pi*" + sFreq$ + "*(x-(" + sLocalStart$ + "))+" + sPhase$ + ")"
                    env$ = "0.5*(1-cos(2*pi*(x-(" + sLocalStart$ + "))/" + sDur$ + "))"
                    term$ = "+if x>=" + sClipStart$ + " and x<" + sClipEnd$ + " then " + sAmp$ + "*" + wave$ + "*" + env$ + " else 0 fi"
                    chunkFormula$ = chunkFormula$ + term$
                endif
            endfor

            maxTermsInChunk = max(maxTermsInChunk, termsInChunk)
            Create Sound from formula: "cgs_m_" + uid$ + "_" + string$(layer) + "_" + string$(chunk),
                ... 1, 0, actualChunkDur, sample_rate_Hz, chunkFormula$
            monoChunkID[chunk] = selected("Sound")
        endfor

        selectObject: monoChunkID[1]
        if num_chunks > 1
            for chunk from 2 to num_chunks
                plusObject: monoChunkID[chunk]
            endfor
            Concatenate
            layerMonoID = selected("Sound")
        else
            Copy: "cgs_layer_m_" + uid$
            layerMonoID = selected("Sound")
        endif

        for chunk to num_chunks
            removeObject: monoChunkID[chunk]
        endfor

        selectObject: mixID
        Formula: "self + object[layerMonoID,1,col]"
        removeObject: layerMonoID

    else
        for chunk to num_chunks
            chunkStart = (chunk - 1) * chunk_duration
            chunkEnd = min(chunk * chunk_duration, duration_s)
            actualChunkDur = chunkEnd - chunkStart
            leftFormula$ = "0"
            rightFormula$ = "0"
            termsInChunk = 0

            for grain to total_grains
                grainStart = grain_time[grain]
                grainEnd = grainStart + grain_dur[grain]

                if grainEnd > chunkStart and grainStart < chunkEnd
                    termsInChunk = termsInChunk + 1
                    if termsInChunk > 180
                        exitScript: "More than 180 overlapping grain terms in one synthesis chunk. Reduce density or grain duration."
                    endif

                    localStart = grainStart - chunkStart
                    localClipStart = max(0, localStart)
                    localClipEnd = min(actualChunkDur, localStart + grain_dur[grain])

                    leftGain = cos(0.5 * pi * grain_pan[grain])
                    rightGain = sin(0.5 * pi * grain_pan[grain])

                    sLocalStart$ = fixed$(localStart, 9)
                    sClipStart$ = fixed$(localClipStart, 9)
                    sClipEnd$ = fixed$(localClipEnd, 9)
                    sDur$ = fixed$(grain_dur[grain], 9)
                    sFreq$ = fixed$(grain_freq[grain], 5)
                    sAmpL$ = fixed$(grain_amp[grain] * leftGain, 7)
                    sAmpR$ = fixed$(grain_amp[grain] * rightGain, 7)
                    sPhase$ = fixed$(grain_phase[grain], 7)

                    wave$ = "sin(2*pi*" + sFreq$ + "*(x-(" + sLocalStart$ + "))+" + sPhase$ + ")"
                    env$ = "0.5*(1-cos(2*pi*(x-(" + sLocalStart$ + "))/" + sDur$ + "))"
                    leftTerm$ = "+if x>=" + sClipStart$ + " and x<" + sClipEnd$ + " then " + sAmpL$ + "*" + wave$ + "*" + env$ + " else 0 fi"
                    rightTerm$ = "+if x>=" + sClipStart$ + " and x<" + sClipEnd$ + " then " + sAmpR$ + "*" + wave$ + "*" + env$ + " else 0 fi"
                    leftFormula$ = leftFormula$ + leftTerm$
                    rightFormula$ = rightFormula$ + rightTerm$
                endif
            endfor

            maxTermsInChunk = max(maxTermsInChunk, termsInChunk)

            Create Sound from formula: "cgs_l_" + uid$ + "_" + string$(layer) + "_" + string$(chunk),
                ... 1, 0, actualChunkDur, sample_rate_Hz, leftFormula$
            leftChunkID[chunk] = selected("Sound")

            Create Sound from formula: "cgs_r_" + uid$ + "_" + string$(layer) + "_" + string$(chunk),
                ... 1, 0, actualChunkDur, sample_rate_Hz, rightFormula$
            rightChunkID[chunk] = selected("Sound")
        endfor

        selectObject: leftChunkID[1]
        if num_chunks > 1
            for chunk from 2 to num_chunks
                plusObject: leftChunkID[chunk]
            endfor
            Concatenate
            layerLeftID = selected("Sound")
        else
            Copy: "cgs_layer_l_" + uid$
            layerLeftID = selected("Sound")
        endif

        selectObject: rightChunkID[1]
        if num_chunks > 1
            for chunk from 2 to num_chunks
                plusObject: rightChunkID[chunk]
            endfor
            Concatenate
            layerRightID = selected("Sound")
        else
            Copy: "cgs_layer_r_" + uid$
            layerRightID = selected("Sound")
        endif

        for chunk to num_chunks
            removeObject: leftChunkID[chunk], rightChunkID[chunk]
        endfor

        selectObject: mixLeftID
        Formula: "self + object[layerLeftID,1,col]"
        selectObject: mixRightID
        Formula: "self + object[layerRightID,1,col]"

        removeObject: layerLeftID, layerRightID
    endif
endfor

# No further random draws are needed.
if seedWasFixed
    random_initializeSafelyAndUnpredictably ()
endif

# ---------------------------------------------------------------------------
# 5. BUILD OUTPUT / EDGE FADE / NORMALIZATION
# ---------------------------------------------------------------------------
if spatial_mode = 1
    final_id = mixID
else
    selectObject: mixLeftID
    plusObject: mixRightID
    Combine to stereo
    final_id = selected("Sound")
    removeObject: mixLeftID, mixRightID
endif

safePreset$ = replace$(preset_name$, " ", "_", 0)
selectObject: final_id
Rename: "chaotic_granular_" + safePreset$

actualFade = min(edge_fade_s, 0.49 * duration_s)
if actualFade > 0
    fadeOutStart = duration_s - actualFade
    selectObject: final_id
    Formula: "if x < actualFade then self*(x/actualFade) else if x > fadeOutStart then self*((duration_s-x)/actualFade) else self fi fi"
endif

if normalize_output
    selectObject: final_id
    preNormPeak = Get absolute extremum: 0, 0, "None"
    if preNormPeak > 0
        Scale peak: 0.90
    endif
endif

selectObject: final_id
final_name$ = selected$("Sound")
final_dur = Get total duration
final_peak = Get absolute extremum: 0, 0, "None"
final_rms = Get root-mean-square: 0, 0
final_channels = Get number of channels

if total_grains_all > 0
    meanDurRealized = durSum / total_grains_all
    realizedDensity = total_grains_all / (duration_s * number_of_layers)
else
    meanDurRealized = 0
    realizedDensity = 0
endif

# ---------------------------------------------------------------------------
# 6. VISUALIZATION
# ---------------------------------------------------------------------------
if draw_visualization
    @drawGranularFigure
endif

# ---------------------------------------------------------------------------
# 7. FINAL INFO / PLAY
# ---------------------------------------------------------------------------
selectObject: final_id
appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE"
appendInfoLine: "=============================================="
appendInfoLine: "Output: ", final_name$
appendInfoLine: "Duration: ", fixed$(final_dur, 3), " s"
appendInfoLine: "Actual grains: ", total_grains_all
appendInfoLine: "Mean realized density: ", fixed$(realizedDensity, 2), " grains/s/layer"
appendInfoLine: "Frequency range: ", fixed$(freqMinRealized,1), "-", fixed$(freqMaxRealized,1), " Hz"
appendInfoLine: "Mean grain duration: ", fixed$(meanDurRealized*1000,1), " ms"
appendInfoLine: "Peak: ", fixed$(final_peak,4), " | RMS: ", fixed$(final_rms,4)
appendInfoLine: "Maximum grain terms in any 1-s layer chunk: ", maxTermsInChunk
appendInfoLine: "Nyquist/low-frequency corrections: ", highFreqCorrections, "/", lowFreqCorrections

if play_after
    Play
endif

selectObject: final_id


# ===========================================================================
# PROCEDURE: RESEARCH-GRADE VISUALIZATION
# ===========================================================================
# ===========================================================================
# FIGURE: QUANTUM -> LAW -> STATISTICS -> SOUND
#
# Granular synthesis descends from Gabor's 1946 "Theory of Communication",
# which tiles the time-frequency plane into elementary cells, each carrying
# one quantum of acoustic information (a "logon"). The control law here comes
# from the other lineage: Lorenz 1963, May 1976, Henon 1976.
#
# The figure follows that order.
#   I   THE INFORMATION DIAGRAM   every rendered grain as its own Gabor cell
#   II  THE DYNAMICAL LAW         bifurcation diagram or attractor, with the
#                                 Lyapunov exponent of the realized orbit
#   III THE INVARIANT MEASURE     the map's own statistics, and the grain
#                                 frequency distribution they produce
#   IV  THE SOUND ITSELF          measured spectrogram
#
# Panels I-III are the CONTROL DOMAIN: they plot the scheduled grain list and
# the chaotic orbit, both recorded during synthesis. Panel IV is the only
# acoustic measurement.
# ===========================================================================
procedure niceStep: .range, .target
    .raw = .range / .target
    .mag = 10 ^ floor(log10(max(1e-12, .raw)))
    .n = .raw / .mag
    if .n < 1.5
        .step = 1 * .mag
    elsif .n < 3.5
        .step = 2 * .mag
    elsif .n < 7.5
        .step = 5 * .mag
    else
        .step = 10 * .mag
    endif
endproc

procedure drawGranularFigure

    .left = 0.80
    .right = 7.55
    .bg$ = "{0.975,0.975,0.978}"
    .grid$ = "{0.80,0.80,0.82}"
    .ink$ = "{0.15,0.15,0.17}"
    .faint$ = "{0.45,0.45,0.52}"
    .cell$ = "{0.30,0.42,0.62}"
    .warm$ = "{0.72,0.42,0.30}"

    # -----------------------------------------------------------------------
    # Gabor cell geometry.
    #
    # For a Hann window of length T the equivalent noise bandwidth is 1.5/T,
    # so the cell area T * (1.5/T) = 1.5 Hz*s is THE SAME for every grain
    # whatever its duration. That is Gabor's quantum: a long grain is a tall
    # thin cell and a short grain a short wide one, but each occupies one
    # cell of the information plane. Occupancy below is therefore driven by
    # the grain COUNT, not by the durations.
    # -----------------------------------------------------------------------
    .cellArea = 1.5
    .fTop = min(safeTop, 1.08 * freqMaxRealized)
    if .fTop <= 0
        .fTop = 1000
    endif
    .occupancy = .cellArea * total_grains_all / (duration_s * .fTop)

    .dtdfSum = 0
    for .g to total_grains_all
        .dtdfSum = .dtdfSum + viz_dur[.g] * (1.5 / viz_dur[.g])
    endfor
    if total_grains_all > 0
        .meanCell = .dtdfSum / total_grains_all
    else
        .meanCell = 0
    endif

    # -----------------------------------------------------------------------
    # Lyapunov exponent OF THE LAW.
    #
    # Computed from a long run (60k iterates), not from the realized orbit:
    # this piece uses on the order of a hundred states, which is far too few
    # for a Lyapunov estimate — a short orbit gave 0.50 for Henon against a
    # converged 0.42. The exponent is a property of the attractor and does
    # not depend on the initial state, so the long run is the right source.
    # -----------------------------------------------------------------------
    .lyap = undefined

    if synthesis_mode = 1
        .zx = 0.31
        for .it to 500
            .zx = logisticR * .zx * (1 - .zx)
        endfor
        .sum = 0
        .n = 0
        for .it to 60000
            .d = abs(logisticR * (1 - 2 * .zx))
            if .d > 1e-12
                .sum = .sum + ln(.d)
                .n = .n + 1
            endif
            .zx = logisticR * .zx * (1 - .zx)
        endfor
        if .n > 0
            .lyap = .sum / .n
        endif

    elsif synthesis_mode = 2
        # Tangent vector carried along the orbit.  J = [ -2a x  1 ; b  0 ]
        .zx = 0.1
        .zy = 0.1
        for .it to 1000
            .nx = 1 - henonA * .zx * .zx + .zy
            .zy = 0.3 * .zx
            .zx = .nx
        endfor
        .u = 1
        .v = 0
        .sum = 0
        .n = 0
        for .it to 60000
            .nu = -2 * henonA * .zx * .u + .v
            .nv = 0.3 * .u
            .norm = sqrt(.nu * .nu + .nv * .nv)
            if .norm > 1e-300
                .sum = .sum + ln(.norm)
                .n = .n + 1
                .u = .nu / .norm
                .v = .nv / .norm
            endif
            .nx = 1 - henonA * .zx * .zx + .zy
            .zy = 0.3 * .zx
            .zx = .nx
        endfor
        if .n > 0
            .lyap = .sum / .n
        endif

    else
        # Benettin two-trajectory method.
        .dt = 0.005
        .ax = 1.0
        .ay = 1.0
        .az = 1.0
        for .i to 4000
            .dx = 10 * (.ay - .ax)
            .dy = .ax * (28 - .az) - .ay
            .dz = .ax * .ay - (8 / 3) * .az
            .ax = .ax + .dt * .dx
            .ay = .ay + .dt * .dy
            .az = .az + .dt * .dz
        endfor
        .d0 = 1e-8
        .bx = .ax + .d0
        .by = .ay
        .bz = .az
        .sum = 0
        .n = 0
        for .i to 40000
            .dx = 10 * (.ay - .ax)
            .dy = .ax * (28 - .az) - .ay
            .dz = .ax * .ay - (8 / 3) * .az
            .ax = .ax + .dt * .dx
            .ay = .ay + .dt * .dy
            .az = .az + .dt * .dz

            .dx = 10 * (.by - .bx)
            .dy = .bx * (28 - .bz) - .by
            .dz = .bx * .by - (8 / 3) * .bz
            .bx = .bx + .dt * .dx
            .by = .by + .dt * .dy
            .bz = .bz + .dt * .dz

            if (.i mod 20) = 0
                .sep = sqrt((.bx - .ax)^2 + (.by - .ay)^2 + (.bz - .az)^2)
                if .sep > 1e-300
                    .sum = .sum + ln(.sep / .d0)
                    .n = .n + 1
                    .sc = .d0 / .sep
                    .bx = .ax + (.bx - .ax) * .sc
                    .by = .ay + (.by - .ay) * .sc
                    .bz = .az + (.bz - .az) * .sc
                endif
            endif
        endfor
        if .n > 0
            .lyap = .sum / (.n * 20 * .dt)
        endif
    endif

    if .lyap <> undefined
        if synthesis_mode = 3
            .lyap$ = "λ ≈ " + fixed$(.lyap, 3) + " per second (Euler dt 0.005)"
        else
            .lyap$ = "λ ≈ " + fixed$(.lyap, 3) + " per iterate"
        endif
    else
        .lyap$ = "λ not computed"
    endif

    Erase all
    Solid line
    Line width: 1

    # =======================================================================
    # TITLE
    # =======================================================================
    Select inner viewport: 0.60, 7.70, 0.06, 0.64
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.84, "half", "##THE INFORMATION DIAGRAM##"
    Font size: 7
    Colour: .faint$
    Text: 0.5, "centre", 0.46, "half",
        ... preset_name$ + "  |  " + string$(number_of_layers) + " layers  |  "
        ... + fixed$(duration_s, 1) + " s  |  " + string$(total_grains_all)
        ... + " grains  |  " + seedLabel$
    Font size: 5
    Text: 0.5, "centre", 0.12, "half",
        ... "after Gabor 1946: the time-frequency plane tiled into elementary cells, "
        ... + "here filled by a deterministic nonlinear law"

    # =======================================================================
    # I. THE INFORMATION DIAGRAM
    #
    # Linear frequency, as in Gabor's own plane: a Hann grain has constant
    # ABSOLUTE bandwidth, so on a linear axis the cells tile evenly and the
    # quantum is visible. A log axis would collapse the high cells to
    # hairlines and hide exactly the point the panel is making.
    # =======================================================================
    Select inner viewport: 0.60, 7.70, 0.84, 1.02
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.0, "left", 0.5, "half", "##I  THE INFORMATION DIAGRAM##"
    Font size: 5
    Colour: .faint$
    Text: 1.0, "right", 0.5, "half",
        ... "control field  —  each grain as its Gabor cell: width = duration, height = 1.5/duration, so every cell has the same area "
        ... + fixed$(.meanCell, 2) + " Hz·s"

    Select inner viewport: .left, .right, 1.08, 2.62
    Axes: 0, duration_s, 0, .fTop
    Paint rectangle: .bg$, 0, duration_s, 0, .fTop

    Select inner viewport: .left, .right, 1.08, 2.62
    Axes: 0, duration_s, 0, .fTop
    Line width: 0.4
    for .g to total_grains_all
        .t0 = viz_time[.g]
        .t1 = .t0 + viz_dur[.g]
        .bwHalf = 0.75 / viz_dur[.g]
        .f0 = viz_freq[.g] - .bwHalf
        .f1 = viz_freq[.g] + .bwHalf
        if .f1 > 0 and .f0 < .fTop and .t0 < duration_s
            .f0 = max(0, .f0)
            .f1 = min(.fTop, .f1)
            .t1 = min(duration_s, .t1)
            # Guarantee a visible cell even for the shortest / narrowest
            # grains, for the same screen-resolution reason as panel II.
            if .t1 - .t0 < duration_s / 600
                .t1 = .t0 + duration_s / 600
            endif
            if .f1 - .f0 < .fTop / 300
                .f1 = .f0 + .fTop / 300
            endif
            .sh = 0.92 - 0.62 * min(1, viz_amp[.g] / max(1e-9, ampMaxRealized))
            .sh$ = fixed$(.sh, 3)
            Paint rectangle: "{" + .sh$ + "," + .sh$ + "," + fixed$(.sh + 0.05, 3) + "}",
                ... .t0, .t1, .f0, .f1
        endif
    endfor

    Select inner viewport: .left, .right, 1.08, 2.62
    Axes: 0, duration_s, 0, .fTop
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 5
    @niceStep: .fTop, 5
    Marks left every: 1, niceStep.step, "yes", "yes", "no"
    @niceStep: duration_s, 8
    Marks bottom every: 1, niceStep.step, "yes", "yes", "no"
    Font size: 6
    Text left: "yes", "Frequency (Hz)"
    Text bottom: "yes", "Time (s)"

    # =======================================================================
    # II. THE DYNAMICAL LAW      III. THE INVARIANT MEASURE
    # =======================================================================
    if synthesis_mode = 1
        .lawTitle$ = "II  THE DYNAMICAL LAW  |  logistic bifurcation, operating point marked"
    elsif synthesis_mode = 2
        .lawTitle$ = "II  THE DYNAMICAL LAW  |  Henon attractor, realized orbit"
    else
        .lawTitle$ = "II  THE DYNAMICAL LAW  |  Lorenz attractor, realized orbit"
    endif

    Select inner viewport: 0.60, 3.85, 2.92, 3.10
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.0, "left", 0.5, "half", "##II  THE DYNAMICAL LAW##"
    Font size: 5
    Colour: .faint$
    if synthesis_mode = 1
        Text: 1.0, "right", 0.5, "half", "logistic bifurcation, operating r marked"
    else
        Text: 1.0, "right", 0.5, "half", "grey: attractor   orange: the "
            ... + string$(chaos_point_count) + " states used"
    endif

    Select inner viewport: 4.25, 7.70, 2.92, 3.10
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.0, "left", 0.5, "half", "##III  THE INVARIANT MEASURE##"

    # --- II ---
    Select inner viewport: 1.05, 3.85, 3.30, 4.46
    if synthesis_mode = 1
        Axes: 3.40, 4.00, 0, 1
        Paint rectangle: .bg$, 3.40, 4.00, 0, 1

        Select inner viewport: 1.05, 3.85, 3.30, 4.46
        Axes: 3.40, 4.00, 0, 1
        # Every mark must have real extent at SCREEN resolution, not only in
        # a 300-dpi export. Sub-pixel line widths and segments shorter than a
        # device pixel can be dropped entirely by the on-screen renderer,
        # which leaves this panel looking empty in the Picture window while
        # the exported PNG looks fine.
        Colour: .ink$
        Line width: 1
        .tick = 0.004
        for .rs to 240
            .r = 3.40 + 0.60 * (.rs - 0.5) / 240
            .bx = 0.35
            for .it to 220
                .bx = .r * .bx * (1 - .bx)
            endfor
            for .it to 40
                .bx = .r * .bx * (1 - .bx)
                Draw line: .r, .bx - .tick, .r, .bx + .tick
            endfor
        endfor

        Select inner viewport: 1.05, 3.85, 3.30, 4.46
        Axes: 3.40, 4.00, 0, 1
        Colour: .warm$
        Line width: 1.2
        Draw line: logisticR, 0, logisticR, 1
        Font size: 5
        Text: logisticR - 0.01, "right", 0.94, "half", "r = " + fixed$(logisticR, 2)

        .xlab$ = "r"
        .ylab$ = "x"
        .lawMarks = 1
    else
        .xMin = 1e30
        .xMax = -1e30
        .yMin = 1e30
        .yMax = -1e30
        for .i to chaos_point_count
            .xMin = min(.xMin, chaos_traj_x[.i])
            .xMax = max(.xMax, chaos_traj_x[.i])
            .yMin = min(.yMin, chaos_traj_y[.i])
            .yMax = max(.yMax, chaos_traj_y[.i])
        endfor
        # widen to the attractor's own extent, since the sample understates it
        if synthesis_mode = 2
            .xMin = min(.xMin, -1.4)
            .xMax = max(.xMax, 1.4)
            .yMin = min(.yMin, -0.42)
            .yMax = max(.yMax, 0.42)
        else
            .xMin = min(.xMin, -20)
            .xMax = max(.xMax, 20)
            .yMin = min(.yMin, -27)
            .yMax = max(.yMax, 27)
        endif
        .xPad = 0.08 * max(1e-9, .xMax - .xMin)
        .yPad = 0.08 * max(1e-9, .yMax - .yMin)
        .xMin = .xMin - .xPad
        .xMax = .xMax + .xPad
        .yMin = .yMin - .yPad
        .yMax = .yMax + .yPad

        Axes: .xMin, .xMax, .yMin, .yMax
        Paint rectangle: .bg$, .xMin, .xMax, .yMin, .yMax

        # The stored orbit holds one state per layer-1 grain, which is far
        # too few to look like an attractor. The attractor itself is drawn
        # faintly from a long re-run of the same law, with the states that
        # actually drove the synthesis marked on top of it.
        Select inner viewport: 1.05, 3.85, 3.30, 4.46
        Axes: .xMin, .xMax, .yMin, .yMax
        if synthesis_mode = 2
            .ax = 0.1
            .ay = 0.1
            for .it to 1000
                .nx = 1 - henonA * .ax * .ax + .ay
                .ay = 0.3 * .ax
                .ax = .nx
            endfor
            for .it to 5000
                .nx = 1 - henonA * .ax * .ax + .ay
                .ay = 0.3 * .ax
                .ax = .nx
                Paint circle (mm): "{0.70,0.70,0.75}", .ax, .ay, 0.22
            endfor
        else
            .dtt = 0.005
            .ax = 1
            .ay = 1
            .az = 1
            for .it to 4000
                .kx = 10 * (.ay - .ax)
                .ky = .ax * (28 - .az) - .ay
                .kz = .ax * .ay - (8 / 3) * .az
                .ax = .ax + .dtt * .kx
                .ay = .ay + .dtt * .ky
                .az = .az + .dtt * .kz
            endfor
            for .it to 5000
                .kx = 10 * (.ay - .ax)
                .ky = .ax * (28 - .az) - .ay
                .kz = .ax * .ay - (8 / 3) * .az
                .ax = .ax + .dtt * .kx
                .ay = .ay + .dtt * .ky
                .az = .az + .dtt * .kz
                Paint circle (mm): "{0.70,0.70,0.75}", .ax, .ay, 0.20
            endfor
        endif

        Select inner viewport: 1.05, 3.85, 3.30, 4.46
        Axes: .xMin, .xMax, .yMin, .yMax
        for .i to chaos_point_count
            Paint circle (mm): .warm$, chaos_traj_x[.i], chaos_traj_y[.i], 0.38
        endfor


        .xlab$ = "x"
        .ylab$ = "y"
        .lawMarks = 0
    endif

    Select inner viewport: 1.05, 3.85, 3.30, 4.46
    if synthesis_mode = 1
        Axes: 3.40, 4.00, 0, 1
    else
        Axes: .xMin, .xMax, .yMin, .yMax
    endif
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 5
    if synthesis_mode = 1
        Marks left every: 1, 0.25, "yes", "yes", "no"
        Marks bottom every: 1, 0.2, "yes", "yes", "no"
    else
        @niceStep: .yMax - .yMin, 4
        Marks left every: 1, niceStep.step, "yes", "yes", "no"
        @niceStep: .xMax - .xMin, 4
        Marks bottom every: 1, niceStep.step, "yes", "yes", "no"
    endif
    Font size: 6
    Text left: "yes", .ylab$
    Text bottom: "yes", .xlab$

    Select inner viewport: 0.60, 3.85, 4.72, 4.90
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: .warm$
    Text: 0.5, "centre", 0.5, "half",
        ... .lyap$ + "   —   the law's exponent, from a long run; positive = chaotic"

    # --- III ---
    # Histogram of the realized chaotic variable: an estimate of the map's
    # invariant density. This is what actually decides how grain parameters
    # cluster, and it is a property of the law, not of the composer's ranges.
    .nBin = 36
    .hMin = 1e30
    .hMax = -1e30
    for .i to chaos_point_count
        .hMin = min(.hMin, chaos_traj_x[.i])
        .hMax = max(.hMax, chaos_traj_x[.i])
    endfor
    if .hMax <= .hMin
        .hMax = .hMin + 1
    endif
    for .b to .nBin
        cgHist[.b] = 0
    endfor
    for .i to chaos_point_count
        .b = ceiling((chaos_traj_x[.i] - .hMin) / (.hMax - .hMin) * .nBin)
        .b = max(1, min(.nBin, .b))
        cgHist[.b] = cgHist[.b] + 1
    endfor
    .hPeak = 1
    for .b to .nBin
        .hPeak = max(.hPeak, cgHist[.b])
    endfor

    # The realized orbit is short — one state per layer-1 grain — so the bars
    # alone are a thin estimate of the law's invariant density. A long re-run
    # of the SAME law gives the density itself, drawn over the bars. The
    # invariant measure is a property of the attractor, so the long run is
    # legitimate even though it is not the orbit that made this sound.
    for .b to .nBin
        cgDens[.b] = 0
    endfor
    .densN = 0
    if synthesis_mode = 1
        .dx = 0.31
        for .it to 500
            .dx = logisticR * .dx * (1 - .dx)
        endfor
        for .it to 60000
            .dx = logisticR * .dx * (1 - .dx)
            .b = ceiling((.dx - .hMin) / (.hMax - .hMin) * .nBin)
            if .b >= 1 and .b <= .nBin
                cgDens[.b] = cgDens[.b] + 1
                .densN = .densN + 1
            endif
        endfor
    elsif synthesis_mode = 2
        .dx = 0.1
        .dy = 0.1
        for .it to 1000
            .nx = 1 - henonA * .dx * .dx + .dy
            .dy = 0.3 * .dx
            .dx = .nx
        endfor
        for .it to 60000
            .nx = 1 - henonA * .dx * .dx + .dy
            .dy = 0.3 * .dx
            .dx = .nx
            .b = ceiling((.dx - .hMin) / (.hMax - .hMin) * .nBin)
            if .b >= 1 and .b <= .nBin
                cgDens[.b] = cgDens[.b] + 1
                .densN = .densN + 1
            endif
        endfor
    else
        .dt = 0.005
        .dx = 1
        .dy = 1
        .dz = 1
        for .it to 4000
            .kx = 10 * (.dy - .dx)
            .ky = .dx * (28 - .dz) - .dy
            .kz = .dx * .dy - (8 / 3) * .dz
            .dx = .dx + .dt * .kx
            .dy = .dy + .dt * .ky
            .dz = .dz + .dt * .kz
        endfor
        for .it to 60000
            .kx = 10 * (.dy - .dx)
            .ky = .dx * (28 - .dz) - .dy
            .kz = .dx * .dy - (8 / 3) * .dz
            .dx = .dx + .dt * .kx
            .dy = .dy + .dt * .ky
            .dz = .dz + .dt * .kz
            .b = ceiling((.dx - .hMin) / (.hMax - .hMin) * .nBin)
            if .b >= 1 and .b <= .nBin
                cgDens[.b] = cgDens[.b] + 1
                .densN = .densN + 1
            endif
        endfor
    endif

    .dPeak = 1
    for .b to .nBin
        .dPeak = max(.dPeak, cgDens[.b])
    endfor

    Select inner viewport: 4.70, 7.70, 3.30, 3.82
    Axes: .hMin, .hMax, 0, 1.15 * .hPeak
    Paint rectangle: .bg$, .hMin, .hMax, 0, 1.15 * .hPeak

    Select inner viewport: 4.70, 7.70, 3.30, 3.82
    Axes: .hMin, .hMax, 0, 1.15 * .hPeak
    for .b to .nBin
        .ba = .hMin + (.b - 1) / .nBin * (.hMax - .hMin)
        .bb = .hMin + .b / .nBin * (.hMax - .hMin)
        Paint rectangle: .cell$, .ba, .bb, 0, cgHist[.b]
    endfor

    Select inner viewport: 4.70, 7.70, 3.30, 3.82
    Axes: .hMin, .hMax, 0, 1.15 * .hPeak
    Colour: .ink$
    Line width: 1.5
    for .b from 2 to .nBin
        .xa = .hMin + (.b - 1.5) / .nBin * (.hMax - .hMin)
        .xb = .hMin + (.b - 0.5) / .nBin * (.hMax - .hMin)
        Draw line: .xa, cgDens[.b - 1] / .dPeak * .hPeak,
            ... .xb, cgDens[.b] / .dPeak * .hPeak
    endfor

    Select inner viewport: 4.70, 7.70, 3.30, 3.82
    Axes: .hMin, .hMax, 0, 1.15 * .hPeak
    Font size: 5
    Colour: .ink$
    Text: .hMin + 0.03 * (.hMax - .hMin), "left", 1.04 * .hPeak, "half",
        ... "state x: bars = " + string$(chaos_point_count)
        ... + " states used, line = invariant density of the law"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 5
    @niceStep: .hMax - .hMin, 4
    Marks bottom every: 1, niceStep.step, "yes", "yes", "no"

    # Grain frequency histogram: the audible consequence of the density above.
    .fMinR = freqMinRealized
    .fMaxR = freqMaxRealized
    if .fMaxR <= .fMinR
        .fMaxR = .fMinR + 1
    endif
    for .b to .nBin
        cgFHist[.b] = 0
    endfor
    for .g to total_grains_all
        .b = ceiling((viz_freq[.g] - .fMinR) / (.fMaxR - .fMinR) * .nBin)
        .b = max(1, min(.nBin, .b))
        cgFHist[.b] = cgFHist[.b] + 1
    endfor
    .fPeak = 1
    for .b to .nBin
        .fPeak = max(.fPeak, cgFHist[.b])
    endfor

    Select inner viewport: 4.70, 7.70, 3.94, 4.46
    Axes: .fMinR, .fMaxR, 0, 1.15 * .fPeak
    Paint rectangle: .bg$, .fMinR, .fMaxR, 0, 1.15 * .fPeak

    Select inner viewport: 4.70, 7.70, 3.94, 4.46
    Axes: .fMinR, .fMaxR, 0, 1.15 * .fPeak
    for .b to .nBin
        .ba = .fMinR + (.b - 1) / .nBin * (.fMaxR - .fMinR)
        .bb = .fMinR + .b / .nBin * (.fMaxR - .fMinR)
        Paint rectangle: .warm$, .ba, .bb, 0, cgFHist[.b]
    endfor

    Select inner viewport: 4.70, 7.70, 3.94, 4.46
    Axes: .fMinR, .fMaxR, 0, 1.15 * .fPeak
    Font size: 5
    Colour: .ink$
    Text: .fMinR + 0.03 * (.fMaxR - .fMinR), "left", 1.02 * .fPeak, "half",
        ... "grain frequency (Hz)"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 5
    @niceStep: .fMaxR - .fMinR, 4
    Marks bottom every: 1, niceStep.step, "yes", "yes", "no"

    Select inner viewport: 4.25, 7.70, 4.72, 4.90
    Axes: 0, 1, 0, 1
    Font size: 5
    Colour: .faint$
    Text: 0.5, "centre", 0.5, "half",
        ... "the shape of the upper histogram is the law's; the lower one inherits it"

    # =======================================================================
    # IV. THE SOUND ITSELF
    # =======================================================================
    Select inner viewport: 0.60, 7.70, 5.14, 5.32
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.0, "left", 0.5, "half", "##IV  THE SOUND ITSELF##"
    Font size: 5
    Colour: .faint$
    Text: 1.0, "right", 0.5, "half",
        ... "measured  —  spectrogram of the rendered output"

    .specStep = max(0.002, duration_s / 1200)
    selectObject: final_id
    .spec = To Spectrogram: 0.025, .fTop, .specStep, 20, "Gaussian"

    Select inner viewport: .left, .right, 5.38, 6.44
    selectObject: .spec
    Paint: 0, 0, 0, .fTop, 100, 1, 50, 6, 0, 0
    removeObject: .spec

    Select inner viewport: .left, .right, 5.38, 6.44
    Axes: 0, duration_s, 0, .fTop
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 5
    @niceStep: .fTop, 5
    Marks left every: 1, niceStep.step, "yes", "yes", "no"
    @niceStep: duration_s, 8
    Marks bottom every: 1, niceStep.step, "yes", "yes", "no"
    Font size: 6
    Text left: "yes", "Frequency (Hz)"
    Text bottom: "yes", "Time (s)"

    # =======================================================================
    # QC SUMMARY
    # =======================================================================
    if synthesis_mode = 1
        .law$ = "Logistic r 3.97 | burn-in 250"
    elsif synthesis_mode = 2
        .law$ = "Henon a 1.4 b 0.3 | burn-in 600"
    else
        .law$ = "Lorenz 10 / 28 / 2.667 | dt 0.005 | burn-in 4000"
    endif

    if normalize_output
        .norm$ = "normalized"
    else
        .norm$ = "raw level"
    endif

    if spatial_mode = 1
        .spatial$ = "Mono"
    else
        .spatial$ = "Stereo Wide"
    endif

    Select inner viewport: 0.60, 7.70, 6.86, 7.52
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.93,0.93,0.935}", 0, 1, 0, 1

    Select inner viewport: 0.60, 7.70, 6.86, 7.52
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.25,0.25,0.25}"
    Text: 0.02, "left", 0.79, "half",
        ... "DYNAMICS  |  " + .law$ + "  |  " + .lyap$ + "  |  " + seedLabel$
    Text: 0.02, "left", 0.50, "half",
        ... "GRAINS  |  " + string$(total_grains_all) + " total  |  density "
        ... + fixed$(realizedDensity, 2) + "/s/layer  |  mean Tg "
        ... + fixed$(meanDurRealized * 1000, 1) + " ms  |  f "
        ... + fixed$(freqMinRealized, 0) + "-" + fixed$(freqMaxRealized, 0)
        ... + " Hz  |  plane occupancy " + fixed$(100 * .occupancy, 2) + "\% "
    Text: 0.02, "left", 0.21, "half",
        ... "OUTPUT  |  peak " + fixed$(final_peak, 3) + "  |  RMS "
        ... + fixed$(final_rms, 4) + "  |  " + .spatial$ + "  |  " + .norm$
        ... + "  |  Nyquist corrections " + string$(highFreqCorrections)

    Select inner viewport: 0.60, 7.70, 6.86, 7.52
    Axes: 0, 1, 0, 1
    Colour: "{0.52,0.52,0.54}"
    Line width: 1
    Draw rectangle: 0, 1, 0, 1

    Select inner viewport: 0.60, 7.70, 7.58, 7.74
    Axes: 0, 1, 0, 1
    Font size: 5
    Colour: "{0.42,0.42,0.42}"
    Text: 0.0, "left", 0.5, "half",
        ... "Panels I–III: control domain, plotted from the scheduled grain list and the realized orbit. "
        ... + "Panel IV: acoustic measurement. Cell height is the Hann equivalent noise bandwidth, not the Gabor uncertainty minimum."

    Colour: "Black"
    Line width: 1
    Font size: 10
endproc
