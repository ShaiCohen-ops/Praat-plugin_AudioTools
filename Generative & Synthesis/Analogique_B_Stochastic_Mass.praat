# ============================================================
# Praat AudioTools - Analogique_B_Stochastic_Mass.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.4 reviewed (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Pure electronic stochastic sound-mass generator inspired by
#   the statistical thinking surrounding Xenakis's Analogique B.
#
#   Signal model:
#       independent white-noise layers
#       -> stochastic time-varying Hann band-pass states
#       -> stochastic amplitude states
#       -> overlap-crossfaded state transitions
#       -> energy-compensated layer sum
#
#   The musical emphasis is the statistical mass rather than
#   individual notes or rhythmic events.
#
# v2.4 reviewed (visualization only; the signal path is unchanged):
#   - Figure re-cast in the graphic vocabulary Xenakis used for Analogique B
#     in Formalized Music, driven entirely by the control-state history the
#     synthesis already records (cfHist#, bwHist#, ampHist#):
#       I   LE LIVRE D'ECRANS   a filmstrip of frequency x intensity screens
#                               sampled across the piece, dots = energy share
#       II  UN ECRAN            one screen enlarged, F and G cell axes labelled
#       III MATRICE DE TRANSITION  empirical transition probabilities between
#                               frequency registers, measured from the walk
#       IV  ATAXIE              normalized entropy of the frequency marginal:
#                               0 = all energy in one register, 1 = even spread
#       V   THE SOUND ITSELF    measured spectrogram with filter-centre paths
#   - Panels II and III replace the former log-frequency filter-field and
#     amplitude-trajectory panels, which the screens and ataxy trace subsume.
#     Panel V is retained deliberately so the formal layer stays anchored to
#     the audio actually produced.
#   - HONEST LIMITS, stated in the figure itself: this is a re-plotting, not
#     an implementation. The signal model is continuous band-limited noise,
#     not a granular screen synthesizer, so the dots are energy quanta rather
#     than Xenakis's grains. The transition matrix is read backwards out of a
#     Gaussian random walk, whereas Analogique B specified its matrix in
#     advance and composed forward from it. Driving the walk FROM a
#     user-specified matrix would make the script Markovian in his sense and
#     remains the obvious next step.
#   - Reports register self-transition probability (diagonal mass of the MTP)
#     in the summary: near 1 means the walk is effectively a birth-death
#     chain on registers, which is what the default drift rates produce.
#   - Figure_language selects English or French labelling throughout the
#     figure. Xenakis published Musiques formelles in French in 1963; the
#     English Formalized Music followed in 1971. Accented characters are
#     written as literal UTF-8: Praat's backslash-quote accent escape does
#     NOT work in Picture text (it swallows the letter), but direct UTF-8
#     renders correctly.
#   - Drawing-order discipline applied throughout: `Text:` and `Draw inner
#     box` leave the drawing frame on the OUTER viewport and a later `Axes:`
#     does not restore it, so every panel re-selects its inner viewport
#     between drawing groups.
#
# v2.4.1 reviewed (labels, provenance and reproducibility; no signal change):
#   - Three labels claimed more than the computation delivered, all of them
#     blurring control-domain against measured-domain:
#       IV  ATAXY -> SPECTRAL ATAXY. It is the entropy of the frequency
#           marginal alone, not of the full F x G screen.
#       III MATRIX OF TRANSITION PROBABILITIES -> FREQUENCY-REGISTER
#           TRANSITION MATRIX. It tracks each layer's centre frequency
#           between six registers, not transitions between whole screens.
#       II  G axis "intensity (dB)" -> "control level (dB)". The value is
#           20*log10(amplitude[layer]), a control state, not measured SPL
#           or RMS. Panel V remains the only acoustic measurement.
#   - Panels I-IV are now marked "control field" and panel V "measured".
#   - Matrix rows carry their sample count n. A row reading 1.00 from two
#     observed transitions is not a probability of one, and short renders
#     produce exactly that. A note states that the matrix describes one
#     realization rather than estimating an underlying chain.
#   - Dot placement inside screen cells is deterministic (a hash of screen,
#     cell and dot index) instead of randomUniform, so the same seed and the
#     same Sound now yield a byte-identical figure. Required for publication.
#   - A cell holding nonzero energy is guaranteed at least one dot; rounding
#     previously let small cells render as empty, which reads as "no energy".
#   - The re-plotting disclaimer moved out of the QC line into its own note
#     strip, and the panel III heading was shortened, for spacing.
#
# v2.3.3 reviewed:
#   - PERFORMANCE FIX: removes the full-duration accumulation canvas introduced
#     in v2.3.2. That design ran a Formula over the entire multi-minute Sound
#     once per stochastic state and could require billions of sample operations.
#   - Restores Praat's efficient Sounds: Concatenate with overlap for each layer.
#   - Preserves the v2.3.2 continuity fix by pre-compensating only the SHORT
#     overlap regions for the Hann crossfade's expected power dip.
#   - For complementary raised-cosine weights w1,w2, the local correction is
#       g(u) = 1/sqrt(w1^2+w2^2) = sqrt(2/(1+cos(pi*u)^2)).
#     Thus uncorrelated adjacent noise states have approximately constant
#     expected power through the overlap, without scanning the full output.
#
# v2.3.2 reviewed:
#   - Continuity fix: replaces raised-cosine amplitude concatenation of
#     independent noise chunks with power-compensated Hann overlap concatenation.
#     This removes the expected ~3 dB power dip at every state boundary.
#   - Transition duration now scales with control-state duration:
#       Normal 1 s states -> 200 ms transition
#       Fast   2 s states -> 400 ms transition
#   - Each filtered chunk is written directly into a full-duration layer
#     canvas; chunk objects are deleted immediately after use.
#   - Visualization/header now identifies equal-power transitions.
#
# v2.3.1 reviewed:
#   - Visualization spacing fix based on rendered Picture QA:
#       shared time-axis labels are no longer repeated under panels A/B,
#       and title/data gaps are increased to prevent collisions.
#   - Added musical morphology presets; Custom remains the default.
#     Presets affect the stochastic mass parameters only, leaving duration,
#     seed, fast mode, normalization, drawing and playback under user control.
#
# v2.3 reviewed:
#   - Separates pass-band width from Hann transition smoothing.
#   - Uses overlap-crossfaded chunks, rather than hard Concatenate,
#     so stochastic filter-state changes do not create hard seams.
#   - Generates noise per chunk instead of holding full-duration
#     noise sources for every layer (substantially lower memory use).
#   - State at chunk n is used for chunk n; the random walk updates
#     between chunks, making the control trajectory semantically clear.
#   - Spectral centre, bandwidth and amplitude walks use reflective
#     boundaries rather than sticky hard clipping.
#   - Bandwidth evolves multiplicatively in log space and stays positive.
#   - Explicit 1/sqrt(N) layer mixing; no multichannel round-trip.
#   - Added reproducible Random_seed (0 = unpredictable).
#   - Added optional output normalization; fade occurs before normalization.
#   - Stronger parameter/workload/Nyquist guards.
#   - Visualization rebuilt around actual DSP states:
#       measured spectrogram + model overlay,
#       actual centre/bandwidth field on log-frequency axis,
#       actual amplitude trajectories,
#       process diagram + governing stochastic rules,
#       compact QC summary.
# ============================================================

form Analogique B - Stochastic Sound Mass v2.3.3
    comment === Morphology preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Balanced Mass
        option Slow Narrow Drift
        option Migrating Bands
        option Turbulent Wide Cloud
        option Low Dark Mass
        option High Spectral Haze
        option Sparse Streams

    comment === Mass parameters ===
    positive Duration_minutes 7.0
    integer Number_of_layers 5
    positive Min_frequency_Hz 60
    positive Max_frequency_Hz 8000
    real Spectral_drift_rate 0.3
    real Bandwidth_variation 0.5
    real Amplitude_turbulence 0.4

    comment === Rendering ===
    integer Random_seed 0
    boolean Fast_mode 0
    boolean Normalize_output 1
    optionmenu Figure_language 1
        option English
        option Francais (Musiques formelles)
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---------------------------------------------------------------------------
# PRESETS
# ---------------------------------------------------------------------------
# Presets describe morphology only. Duration, seed and render controls remain
# independent so a short audition and a long-form render use the same preset.
presetName$ = "Custom"

if preset = 2
    presetName$ = "Balanced Mass"
    number_of_layers = 5
    min_frequency_Hz = 60
    max_frequency_Hz = 8000
    spectral_drift_rate = 0.30
    bandwidth_variation = 0.50
    amplitude_turbulence = 0.40

elsif preset = 3
    presetName$ = "Slow Narrow Drift"
    number_of_layers = 4
    min_frequency_Hz = 120
    max_frequency_Hz = 5000
    spectral_drift_rate = 0.12
    bandwidth_variation = 0.18
    amplitude_turbulence = 0.18

elsif preset = 4
    presetName$ = "Migrating Bands"
    number_of_layers = 5
    min_frequency_Hz = 80
    max_frequency_Hz = 8000
    spectral_drift_rate = 0.65
    bandwidth_variation = 0.30
    amplitude_turbulence = 0.22

elsif preset = 5
    presetName$ = "Turbulent Wide Cloud"
    number_of_layers = 8
    min_frequency_Hz = 50
    max_frequency_Hz = 9000
    spectral_drift_rate = 0.45
    bandwidth_variation = 0.85
    amplitude_turbulence = 0.75

elsif preset = 6
    presetName$ = "Low Dark Mass"
    number_of_layers = 6
    min_frequency_Hz = 40
    max_frequency_Hz = 2200
    spectral_drift_rate = 0.28
    bandwidth_variation = 0.55
    amplitude_turbulence = 0.45

elsif preset = 7
    presetName$ = "High Spectral Haze"
    number_of_layers = 7
    min_frequency_Hz = 1500
    max_frequency_Hz = 9500
    spectral_drift_rate = 0.35
    bandwidth_variation = 0.65
    amplitude_turbulence = 0.35

elsif preset = 8
    presetName$ = "Sparse Streams"
    number_of_layers = 3
    min_frequency_Hz = 100
    max_frequency_Hz = 6500
    spectral_drift_rate = 0.35
    bandwidth_variation = 0.15
    amplitude_turbulence = 0.30
endif

startTime = stopwatch

# ---------------------------------------------------------------------------
# 0. CONSTANTS / VALIDATION
# ---------------------------------------------------------------------------
sampleRate = 44100
nyquist = sampleRate / 2
duration_s = duration_minutes * 60

if duration_s <= 0
    exitScript: "Duration must be greater than zero."
endif

if number_of_layers < 1
    exitScript: "Number of layers must be at least 1."
endif
if number_of_layers > 32
    exitScript: "Number of layers is limited to 32 to keep processing and memory bounded."
endif

if min_frequency_Hz < 20
    min_frequency_Hz = 20
endif
safeMaxFrequency = 0.90 * nyquist
if max_frequency_Hz > safeMaxFrequency
    max_frequency_Hz = safeMaxFrequency
endif
if max_frequency_Hz <= min_frequency_Hz
    exitScript: "Max frequency must be greater than Min frequency after Nyquist protection."
endif

if spectral_drift_rate < 0
    exitScript: "Spectral drift rate cannot be negative."
endif
if bandwidth_variation < 0
    exitScript: "Bandwidth variation cannot be negative."
endif
if amplitude_turbulence < 0
    exitScript: "Amplitude turbulence cannot be negative."
endif
if random_seed < 0
    exitScript: "Random seed must be 0 (unpredictable) or a positive integer."
endif

# Fast mode changes temporal control resolution, not the underlying
# per-second random-walk scaling.
if fast_mode
    chunkDur = 2.0
    noiseFormula$ = "randomUniform(-0.8660254, 0.8660254)"
    fastSuffix$ = "_fast"
    modeStr$ = "FAST"
else
    chunkDur = 1.0
    noiseFormula$ = "randomGauss(0, 0.5)"
    fastSuffix$ = ""
    modeStr$ = "NORMAL"
endif

# Random-walk increments scale with sqrt(dt).
driftScale = sqrt(chunkDur)

# Smooth state transitions with equal-power overlap-add.
# Praat's Concatenate with overlap uses complementary amplitude fades; for
# independent noise this produces an expected power dip in the overlap.
# Here adjacent stochastic states use sin/cos equal-power windows instead.
crossfadeDur = min(0.50, 0.20 * chunkDur)

# Gentle global edges.
fadeDur = min(2.0, 0.10 * duration_s)

numChunks = ceiling(duration_s / chunkDur)
filterCalls = number_of_layers * numChunks
if filterCalls > 50000
    exitScript: "This setting would require more than 50,000 filter calls. Reduce duration/layers or use Fast mode."
endif

# Reproducibility.
seedWasFixed = 0
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedWasFixed = 1
    seedLabel$ = "seed " + string$(random_seed)
else
    seedLabel$ = "seed random"
endif

# ---------------------------------------------------------------------------
# 1. INFO
# ---------------------------------------------------------------------------
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  ANALOGIQUE B - STOCHASTIC SOUND MASS v2.3.3"
writeInfoLine: "  Xenakis-inspired statistical mass model"
writeInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Duration: ", fixed$(duration_s / 60, 2), " minutes"
appendInfoLine: "Layers: ", number_of_layers
appendInfoLine: "Spectral range: ", fixed$(min_frequency_Hz, 0), " - ", fixed$(max_frequency_Hz, 0), " Hz"
appendInfoLine: "Control state: ", fixed$(chunkDur, 2), " s | equal-power compensated overlap: ", fixed$(crossfadeDur * 1000, 0), " ms"
appendInfoLine: "Randomness: ", seedLabel$
appendInfoLine: "Mode: ", modeStr$
appendInfoLine: ""

# ---------------------------------------------------------------------------
# 2. STOCHASTIC STATE INITIALIZATION
# ---------------------------------------------------------------------------
appendInfoLine: "Stage 1: Initializing stochastic layer states..."

logMinBound = ln(min_frequency_Hz)
logMaxBound = ln(max_frequency_Hz)
logSpan = logMaxBound - logMinBound

for layer to number_of_layers
    centerFreq[layer] = exp(randomUniform(logMinBound, logMaxBound))
    bandwidth[layer] = centerFreq[layer] * randomUniform(0.20, 0.80)
    amplitude[layer] = randomUniform(0.30, 0.80)
endfor

# Actual histories used by the DSP.
nHistory = number_of_layers * numChunks
cfHist# = zero#(nHistory)
bwHist# = zero#(nHistory)
ampHist# = zero#(nHistory)

globalCfMin = max_frequency_Hz
globalCfMax = min_frequency_Hz
globalBwMin = max_frequency_Hz
globalBwMax = 0
globalAmpMin = 1
globalAmpMax = 0
boundaryEvents = 0

# ---------------------------------------------------------------------------
# 3. GENERATE / FILTER EACH LAYER
# ---------------------------------------------------------------------------
appendInfoLine: "Stage 2: Generating and filtering stochastic layers..."

for layer to number_of_layers
    # Keep only one layer's short state chunks in memory. Praat performs the
    # full-duration assembly once, after all chunks for this layer are ready.
    layerParts# = zero#(numChunks)

    for chunk to numChunks
        coreStart = (chunk - 1) * chunkDur
        coreEnd = min(chunk * chunkDur, duration_s)
        coreDur = coreEnd - coreStart

        # Every chunk after the first carries one extra overlap at its head.
        # Sounds: Concatenate with overlap removes exactly this amount at each
        # junction, so the assembled layer still has duration_s samples.
        if chunk = 1
            extraBefore = 0
        else
            extraBefore = crossfadeDur
        endif
        partDur = coreDur + extraBefore

        if partDur > 0
            # ----- Actual state used for this chunk -----
            histIndex = (layer - 1) * numChunks + chunk
            cfHist#[histIndex] = centerFreq[layer]
            bwHist#[histIndex] = bandwidth[layer]
            ampHist#[histIndex] = amplitude[layer]

            globalCfMin = min(globalCfMin, centerFreq[layer])
            globalCfMax = max(globalCfMax, centerFreq[layer])
            globalBwMin = min(globalBwMin, bandwidth[layer])
            globalBwMax = max(globalBwMax, bandwidth[layer])
            globalAmpMin = min(globalAmpMin, amplitude[layer])
            globalAmpMax = max(globalAmpMax, amplitude[layer])

            # Independent stochastic carrier for this state.
            Create Sound from formula: "ab_noise", 1, 0, partDur, sampleRate, noiseFormula$
            rawID = selected("Sound")

            lowCut = max(20, centerFreq[layer] - 0.5 * bandwidth[layer])
            highCut = min(0.95 * nyquist, centerFreq[layer] + 0.5 * bandwidth[layer])
            passWidth = highCut - lowCut

            if passWidth < 10
                midCut = 0.5 * (lowCut + highCut)
                lowCut = max(20, midCut - 5)
                highCut = min(0.95 * nyquist, midCut + 5)
                passWidth = highCut - lowCut
            endif

            transitionHz = min(120, max(8, 0.15 * passWidth))

            selectObject: rawID
            Filter (pass Hann band): lowCut, highCut, transitionHz
            filteredID = selected("Sound")
            removeObject: rawID

            ampVal = amplitude[layer]
            selectObject: filteredID
            Formula: "self * ampVal"

            # Praat's Concatenate with overlap uses complementary raised-cosine
            # amplitude fades. For independent noises, w1^2+w2^2 falls to 0.5
            # at the midpoint. Correct ONLY the short overlap regions by
            # g(u)=sqrt(2/(1+cos(pi*u)^2)); after Praat applies its fades,
            # expected overlap power is approximately constant.
            if crossfadeDur > 0 and numChunks > 1
                if chunk > 1
                    overlapLen = min(crossfadeDur, partDur)
                    if overlapLen > 0
                        Formula: "self * if x < overlapLen then sqrt(2/(1+cos(pi*x/overlapLen)^2)) else 1 fi"
                    endif
                endif

                if chunk < numChunks
                    overlapLen = min(crossfadeDur, partDur)
                    overlapStart = partDur - overlapLen
                    if overlapLen > 0
                        Formula: "self * if x > overlapStart then sqrt(2/(1+cos(pi*(x-overlapStart)/overlapLen)^2)) else 1 fi"
                    endif
                endif
            endif

            layerParts#[chunk] = filteredID

            # ----- Evolve state BETWEEN chunks -----
            if chunk < numChunks
                drift = randomGauss(0, spectral_drift_rate * 0.10 * driftScale)
                rawLogFreq = ln(centerFreq[layer]) + drift

                if rawLogFreq < logMinBound or rawLogFreq > logMaxBound
                    boundaryEvents = boundaryEvents + 1
                endif

                unitPos = (rawLogFreq - logMinBound) / logSpan
                folded = unitPos - 2 * floor(unitPos / 2)
                if folded > 1
                    folded = 2 - folded
                endif
                centerFreq[layer] = exp(logMinBound + folded * logSpan)

                bwStep = randomGauss(0, bandwidth_variation * 0.08 * driftScale)
                newBw = bandwidth[layer] * exp(bwStep)
                minBw = max(30, 0.10 * centerFreq[layer])
                maxBw = min(0.80 * nyquist, 1.50 * centerFreq[layer])
                if maxBw < minBw
                    maxBw = minBw
                endif

                if newBw < minBw
                    newBw = minBw + (minBw - newBw)
                    boundaryEvents = boundaryEvents + 1
                endif
                if newBw > maxBw
                    newBw = maxBw - (newBw - maxBw)
                    boundaryEvents = boundaryEvents + 1
                endif
                newBw = max(minBw, min(maxBw, newBw))
                bandwidth[layer] = newBw

                ampLow = 0.05
                ampHigh = 1.00
                ampSpan = ampHigh - ampLow
                rawAmp = amplitude[layer] + randomGauss(0, amplitude_turbulence * 0.10 * driftScale)

                if rawAmp < ampLow or rawAmp > ampHigh
                    boundaryEvents = boundaryEvents + 1
                endif

                ampPos = (rawAmp - ampLow) / ampSpan
                ampFolded = ampPos - 2 * floor(ampPos / 2)
                if ampFolded > 1
                    ampFolded = 2 - ampFolded
                endif
                amplitude[layer] = ampLow + ampFolded * ampSpan
            endif
        endif
    endfor

    # One optimized full-layer assembly instead of one full-duration Formula
    # per chunk. Objects were created chronologically, which is the order used
    # by Sounds: Concatenate with overlap.
    selectObject: layerParts#[1]
    for chunk from 2 to numChunks
        if layerParts#[chunk] > 0
            plusObject: layerParts#[chunk]
        endif
    endfor

    if numChunks > 1 and crossfadeDur > 0
        Concatenate with overlap: crossfadeDur
    else
        Concatenate
    endif

    processedLayer[layer] = selected("Sound")
    Rename: "ab_layer_" + string$(layer)

    for chunk to numChunks
        if layerParts#[chunk] > 0
            removeObject: layerParts#[chunk]
        endif
    endfor

    appendInfoLine: "  Layer ", layer, "/", number_of_layers, " complete"
endfor

# All random draws are finished. Do not leave Praat's global RNG fixed.
if seedWasFixed
    random_initializeSafelyAndUnpredictably ()
endif

# ---------------------------------------------------------------------------
# 4. ENERGY-COMPENSATED MONO LAYER SUM
# ---------------------------------------------------------------------------
appendInfoLine: "Stage 3: Mixing layers..."

Create Sound from formula: "ab_mix", 1, 0, duration_s, sampleRate, "0"
outputID = selected("Sound")
mixScale = 1 / sqrt(number_of_layers)

for layer to number_of_layers
    sourceLayerID = processedLayer[layer]
    selectObject: outputID
    Formula: "self + mixScale * object[sourceLayerID, 1, col]"
endfor

for layer to number_of_layers
    removeObject: processedLayer[layer]
endfor

# Global edge envelope in one Formula, so short durations cannot receive
# multiple sequential fade multiplications.
selectObject: outputID
fadeOutStart = duration_s - fadeDur
Formula: "if x < fadeDur then self * (x / fadeDur) else if x > fadeOutStart then self * ((duration_s - x) / fadeDur) else self fi fi"

# Generator-level normalization is optional and occurs AFTER the fades.
if normalize_output
    preNormPeak = Get absolute extremum: 0, 0, "None"
    if preNormPeak > 0
        Scale peak: 0.90
    endif
endif

Rename: "analogique_b_" + fixed$(duration_minutes, 1) + "min" + fastSuffix$

processingTime = stopwatch
if processingTime < 0
    processingTime = 0
endif

selectObject: outputID
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"
finalRMS = Get root-mean-square: 0, 0

appendInfoLine: ""
appendInfoLine: "Processing time: ", fixed$(processingTime, 1), " seconds"
appendInfoLine: "Output peak: ", fixed$(finalPeak, 3)
appendInfoLine: "Output RMS: ", fixed$(finalRMS, 4)

# ---------------------------------------------------------------------------
# 5. VISUALIZATION
# ---------------------------------------------------------------------------
if draw_visualization
    @drawMassFigure: finalDur
endif

# ---------------------------------------------------------------------------
# 6. FINAL INFO / PLAY
# ---------------------------------------------------------------------------
selectObject: outputID

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE"
appendInfoLine: "=============================================="
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(finalDur / 60, 2), " minutes"
appendInfoLine: "Filter calls: ", filterCalls
appendInfoLine: "Boundary reflections: ", boundaryEvents
appendInfoLine: "Randomness: ", seedLabel$

if play_result
    Play
endif

selectObject: outputID


# ===========================================================================
# ===========================================================================
# PROCEDURE: FIGURE IN THE NOTATION OF FORMALIZED MUSIC
#
# The four upper panels re-plot the control-state history the synthesis
# already recorded (cfHist#, bwHist#, ampHist#) in the coordinates Xenakis
# used for Analogique B: screens on a frequency x intensity plane, a book
# of screens along time, a matrix of transition probabilities between
# frequency registers, and an ataxy (disorder) trace.
#
# This is a RE-PLOTTING, not an implementation. The signal model here is
# continuous band-limited noise, not a granular screen synthesizer, so the
# dots are energy quanta and not Xenakis's grains. The transition matrix is
# measured out of a Gaussian random walk after the fact, whereas Analogique
# B specified its matrix in advance and composed forward from it. Panel V
# carries the measured spectrogram so the formal layer stays anchored to
# the sound actually produced.
# ===========================================================================
procedure drawMassFigure: .duration

    .leftViewport = 0.90
    .rightViewport = 7.70
    .ink$ = "{0.15, 0.15, 0.17}"
    .grid$ = "{0.62, 0.62, 0.66}"
    .faint$ = "{0.45, 0.45, 0.52}"
    .bg$ = "{0.975, 0.975, 0.978}"
    .model1$ = "{0.18, 0.44, 0.72}"
    .model2$ = "{0.72, 0.36, 0.24}"
    .model3$ = "{0.30, 0.58, 0.38}"

    if .duration <= 10
        .tTick = 1
    elsif .duration <= 30
        .tTick = 5
    elsif .duration <= 120
        .tTick = 20
    else
        .tTick = 60
    endif

    abNF = 8
    abNG = 5
    abNR = 6
    # G is INTENSITY, so the cells are dB, not linear amplitude. The walk's
    # amplitude floor is 0.05, which sets the bottom of the scale.
    abGminDb = 20 * log10(0.05)
    abLogMin = ln(min_frequency_Hz)
    abLogMax = ln(max_frequency_Hz)
    abLogSpan = abLogMax - abLogMin
    if abLogSpan <= 0
        abLogSpan = 1
    endif

    # -----------------------------------------------------------------------
    # Frequency marginal per control state, and the ataxy trace.
    # Ataxy is the entropy of that marginal, normalized so that 0 means all
    # energy in one register and 1 means energy spread evenly.
    # -----------------------------------------------------------------------
    for .c to numChunks
        for .i to abNF
            abFm[.c, .i] = 0
        endfor
        .tot = 0

        for .lay to number_of_layers
            .idx = (.lay - 1) * numChunks + .c
            .cf = cfHist#[.idx]
            .bwv = bwHist#[.idx]
            .amp = ampHist#[.idx]

            if .cf > 0 and .amp > 0
                .lo = ln(max(min_frequency_Hz, .cf - 0.5 * .bwv))
                .hi = ln(min(max_frequency_Hz, .cf + 0.5 * .bwv))
                if .hi > .lo
                    .enr = .amp * .amp
                    for .i to abNF
                        .fa = abLogMin + (.i - 1) / abNF * abLogSpan
                        .fb = abLogMin + .i / abNF * abLogSpan
                        .ov = min(.hi, .fb) - max(.lo, .fa)
                        if .ov > 0
                            .share = .enr * .ov / (.hi - .lo)
                            abFm[.c, .i] = abFm[.c, .i] + .share
                            .tot = .tot + .share
                        endif
                    endfor
                endif
            endif
        endfor

        abFmTot[.c] = .tot

        .h = 0
        if .tot > 0
            for .i to abNF
                .p = abFm[.c, .i] / .tot
                if .p > 0
                    .h = .h - .p * ln(.p)
                endif
            endfor
        endif
        abAtaxy[.c] = .h / ln(abNF)
    endfor

    # -----------------------------------------------------------------------
    # Empirical matrix of transition probabilities over frequency registers.
    # -----------------------------------------------------------------------
    for .a to abNR
        abRowTot[.a] = 0
        for .b to abNR
            abMtp[.a, .b] = 0
        endfor
    endfor

    for .c from 1 to numChunks - 1
        for .lay to number_of_layers
            .i1 = (.lay - 1) * numChunks + .c
            .i2 = .i1 + 1
            .f1 = cfHist#[.i1]
            .f2 = cfHist#[.i2]
            if .f1 > 0 and .f2 > 0
                .ra = ceiling((ln(.f1) - abLogMin) / abLogSpan * abNR)
                .rb = ceiling((ln(.f2) - abLogMin) / abLogSpan * abNR)
                .ra = max(1, min(abNR, .ra))
                .rb = max(1, min(abNR, .rb))
                abMtp[.ra, .rb] = abMtp[.ra, .rb] + 1
                abRowTot[.ra] = abRowTot[.ra] + 1
            endif
        endfor
    endfor

    # Diagonal mass: how often a layer stays in its register from one state
    # to the next. Near 1 means the walk is effectively a birth-death chain.
    .diagHits = 0
    .allHits = 0
    for .a to abNR
        .diagHits = .diagHits + abMtp[.a, .a]
        .allHits = .allHits + abRowTot[.a]
    endfor
    if .allHits > 0
        abDiag = .diagHits / .allHits
    else
        abDiag = undefined
    endif

    # -----------------------------------------------------------------------
    # LABELS. Accented characters are literal UTF-8: Praat's backslash-quote
    # accent escape does not work in Picture text, it swallows the letter.
    # -----------------------------------------------------------------------
    if figure_language = 2
        .lTitle$ = "ANALOGIQUE B  —  LIVRE D'ÉCRANS"
        .lGloss$ = "le champ de contrôle réalisé, replacé dans les coordonnées de Musiques formelles ; le panneau V est le son effectivement produit"
        .lLayers$ = " couches"
        .lScreens$ = " s par écran"
        .lMin$ = " min"
        .l1$ = "I  LE LIVRE D'ÉCRANS"
        .l1cap$ = "chaque écran : fréquence (" + string$(abNF) + " cases) par intensité (" + string$(abNG) + " cases) ; points = part de l'énergie"
        .l2$ = "II  UN ÉCRAN"
        .l2at$ = "écran à "
        .lF$ = "F   fréquence (Hz), échelle logarithmique"
        .lG$ = "G   niveau de contrôle (dB)"
        .l3$ = "III  MATRICE DE TRANSITION DE REGISTRE"
        .l3to$ = "vers le registre (grave à aigu)"
        .l3from$ = "depuis le registre ; n = transitions observées, lignes vides jamais occupées"
        .l4$ = "IV  ATAXIE SPECTRALE"
        .l4cap$ = "entropie de la répartition en fréquence seule, non de l'écran F×G ; 0 = un seul registre, 1 = répartition égale"
        .lAtaxy$ = "ataxie spectrale"
        .l5$ = "V  LE SON LUI-MÊME"
        .l5cap$ = "spectrogramme mesuré, avec les trajectoires réelles des centres de filtrage"
        .lFreq$ = "Fréquence (Hz)"
        .lTime$ = "Temps (s)"
        .lField$ = "CHAMP  |  centre "
        .lBw$ = " Hz  |  largeur de bande "
        .lAmp$ = " Hz  |  amplitude "
        .lRefl$ = "  |  réflexions "
        .lCtrl$ = "CONTRÔLE  |  dérive "
        .lBwVar$ = "  |  variation de bande "
        .lTurb$ = "  |  turbulence "
        .lXfade$ = "  |  puissance constante "
        .lSelf$ = " ms  |  auto-transition de registre "
        .lOut$ = "SORTIE  |  "
        .lLayers2$ = " couches  |  "
        .lStates$ = " états de filtrage  |  crête "
        .lRms$ = "  |  RMS "
        .lDisc$ = ""
        .lNote$ = "Panneaux I–IV : champ de contrôle, report des états enregistrés — non une synthèse granulaire. Panneau V : mesure acoustique. La matrice décrit une réalisation, non une chaîne sous-jacente estimée."
        .lCtlDom$ = "champ de contrôle"
        .lMeasDom$ = "mesuré"
        .lNorm$ = "normalisé"
        .lRaw$ = "niveau brut"
        .lSeed$ = "graine "
        .lSeedR$ = "graine aléatoire"
    else
        .lTitle$ = "ANALOGIQUE B  —  THE BOOK OF SCREENS"
        .lGloss$ = "the realized control field re-plotted in the coordinates of Formalized Music; panel V is the sound actually produced"
        .lLayers$ = " layers"
        .lScreens$ = " s screens"
        .lMin$ = " min"
        .l1$ = "I  THE BOOK OF SCREENS"
        .l1cap$ = "each screen: frequency (" + string$(abNF) + " cells) by intensity (" + string$(abNG) + " cells); dots = share of energy"
        .l2$ = "II  ONE SCREEN"
        .l2at$ = "screen at "
        .lF$ = "F   frequency (Hz), logarithmic"
        .lG$ = "G   control level (dB)"
        .l3$ = "III  FREQUENCY-REGISTER TRANSITION MATRIX"
        .l3to$ = "to register (low to high)"
        .l3from$ = "from register; n = transitions observed, blank rows never occupied"
        .l4$ = "IV  SPECTRAL ATAXY"
        .l4cap$ = "entropy of the frequency distribution alone, not of the F×G screen; 0 = one register, 1 = evenly spread"
        .lAtaxy$ = "spectral ataxy"
        .l5$ = "V  THE SOUND ITSELF"
        .l5cap$ = "measured spectrogram with the actual filter-centre paths overlaid"
        .lFreq$ = "Frequency (Hz)"
        .lTime$ = "Time (s)"
        .lField$ = "FIELD  |  centre "
        .lBw$ = " Hz  |  bandwidth "
        .lAmp$ = " Hz  |  amplitude "
        .lRefl$ = "  |  reflections "
        .lCtrl$ = "CONTROL  |  drift "
        .lBwVar$ = "  |  BW variation "
        .lTurb$ = "  |  turbulence "
        .lXfade$ = "  |  equal-power "
        .lSelf$ = " ms  |  register self-transition "
        .lOut$ = "OUTPUT  |  "
        .lLayers2$ = " layers  |  "
        .lStates$ = " filter states  |  peak "
        .lRms$ = "  |  RMS "
        .lDisc$ = ""
        .lNote$ = "Panels I–IV: control field, a re-plotting of the recorded states — not a grain synthesis. Panel V: acoustic measurement. The matrix describes one realization, not an estimate of an underlying chain."
        .lCtlDom$ = "control field"
        .lMeasDom$ = "measured"
        .lNorm$ = "normalized"
        .lRaw$ = "raw level"
        .lSeed$ = "seed "
        .lSeedR$ = "random seed"
    endif

    if random_seed > 0
        .seed$ = .lSeed$ + string$(random_seed)
    else
        .seed$ = .lSeedR$
    endif

    Erase all
    Solid line
    Line width: 1

    # =======================================================================
    # TITLE
    # =======================================================================
    Select inner viewport: 0.60, 7.70, 0.12, 0.52
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.76, "half", "##" + .lTitle$ + "##"
    Font size: 6
    Colour: .faint$
    Text: 0.5, "centre", 0.28, "half",
        ... presetName$ + "  |  " + string$(number_of_layers) + .lLayers$ + "  |  "
        ... + fixed$(chunkDur, 1) + .lScreens$ + "  |  " + fixed$(.duration / 60, 2)
        ... + .lMin$ + "  |  " + .seed$
    Text: 0.5, "centre", 0.04, "half",
        ... .lGloss$

    # =======================================================================
    # I. THE BOOK OF SCREENS
    # =======================================================================
    Select inner viewport: 0.60, 7.70, 0.86, 1.04
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.0, "left", 0.5, "half", "##" + .l1$ + "##"
    Font size: 5
    Colour: .faint$
    Text: 1.0, "right", 0.5, "half",
        ... .lCtlDom$ + "  —  " + .l1cap$

    abShown = 10
    if numChunks < abShown
        abShown = numChunks
    endif

    Select inner viewport: 0.60, 7.70, 1.10, 1.96
    Axes: 0, abShown, 0, 1

    for .k to abShown
        if abShown > 1
            abC = round(1 + (.k - 1) * (numChunks - 1) / (abShown - 1))
        else
            abC = 1
        endif
        @buildScreen: abC
        @paintScreen: .k - 0.94, .k - 0.10, 0.22, 0.97, 0.34, 46
    endfor

    Select inner viewport: 0.60, 7.70, 1.10, 1.96
    Axes: 0, abShown, 0, 1
    Font size: 5
    Colour: .faint$
    for .k to abShown
        if abShown > 1
            abC = round(1 + (.k - 1) * (numChunks - 1) / (abShown - 1))
        else
            abC = 1
        endif
        Text: .k - 0.53, "centre", 0.10, "half", fixed$((abC - 1) * chunkDur, 0) + " s"
    endfor

    Select inner viewport: 0.60, 7.70, 1.10, 1.96
    Axes: 0, abShown, 0, 1
    Colour: .ink$
    Line width: 1
    Draw arrow: 0.03, 0.02, abShown - 0.03, 0.02

    # =======================================================================
    # II. ONE SCREEN     III. MATRIX OF TRANSITION PROBABILITIES
    # =======================================================================
    Select inner viewport: 0.60, 3.85, 2.26, 2.44
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.0, "left", 0.5, "half", "##" + .l2$ + "##"

    Select inner viewport: 4.20, 7.70, 2.26, 2.44
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.0, "left", 0.5, "half", "##" + .l3$ + "##"

    abMid = max(1, round(numChunks / 2))
    @buildScreen: abMid

    Select inner viewport: 1.10, 3.85, 2.78, 4.00
    Axes: 0, 1, 0, 1
    @paintScreen: 0, 1, 0, 1, 0.55, 150

    Select inner viewport: 1.10, 3.85, 2.78, 4.00
    Axes: 0, 1, 0, 1
    Font size: 5
    Colour: .faint$
    for .i from 0 to abNF
        .f = exp(abLogMin + .i / abNF * abLogSpan)
        if .f >= 1000
            .lab$ = fixed$(.f / 1000, 1) + "k"
        else
            .lab$ = fixed$(.f, 0)
        endif
        Text: .i / abNF, "centre", -0.06, "half", .lab$
    endfor
    Text: 0.5, "centre", -0.16, "half", .lF$
    for .j from 0 to abNG
        .db = abGminDb + .j / abNG * (0 - abGminDb)
        Text: -0.03, "right", .j / abNG, "half", fixed$(.db, 0)
    endfor
    Text: -0.15, "centre", 0.5, "half", .lG$
    Text: 0.5, "centre", 1.08, "half",
        ... .l2at$ + fixed$((abMid - 1) * chunkDur, 0) + " s"

    # --- MTP ---
    Select inner viewport: 4.70, 6.90, 2.78, 4.00
    Axes: 0, abNR, 0, abNR
    for .a to abNR
        for .b to abNR
            if abRowTot[.a] > 0
                .p = abMtp[.a, .b] / abRowTot[.a]
            else
                .p = 0
            endif
            .g = 1 - 0.82 * .p
            .g$ = fixed$(.g, 3)
            Paint rectangle: "{" + .g$ + ", " + .g$ + ", " + .g$ + "}",
                ... .b - 1, .b, abNR - .a, abNR - .a + 1
        endfor
    endfor

    Select inner viewport: 4.70, 6.90, 2.78, 4.00
    Axes: 0, abNR, 0, abNR
    Colour: .grid$
    Line width: 0.6
    for .i from 0 to abNR
        Draw line: .i, 0, .i, abNR
        Draw line: 0, .i, abNR, .i
    endfor
    Colour: .ink$
    Line width: 1
    Draw rectangle: 0, abNR, 0, abNR

    Select inner viewport: 4.70, 6.90, 2.78, 4.00
    Axes: 0, abNR, 0, abNR
    Font size: 4
    for .a to abNR
        for .b to abNR
            if abRowTot[.a] > 0
                .p = abMtp[.a, .b] / abRowTot[.a]
            else
                .p = 0
            endif
            if .p >= 0.005
                if .p > 0.55
                    Colour: "White"
                else
                    Colour: .ink$
                endif
                Text: .b - 0.5, "centre", abNR - .a + 0.5, "half", fixed$(.p, 2)
            endif
        endfor
    endfor

    Select inner viewport: 4.70, 6.90, 2.78, 4.00
    Axes: 0, abNR, 0, abNR
    Font size: 5
    Colour: .faint$
    for .b to abNR
        Text: .b - 0.5, "centre", -0.35, "half", "R" + string$(.b)
    endfor
    for .a to abNR
        Text: -0.20, "right", abNR - .a + 0.5, "half", "R" + string$(.a)
        # A row's probabilities are only as good as the transitions behind
        # them: 1.00 from n=2 is not a probability of one.
        Text: abNR + 0.20, "left", abNR - .a + 0.5, "half",
            ... "n=" + string$(abRowTot[.a])
    endfor
    Text: abNR / 2, "centre", -0.95, "half", .l3to$
    Text: abNR / 2, "centre", abNR + 0.45, "half",
        ... .l3from$

    # =======================================================================
    # IV. ATAXY
    # =======================================================================
    Select inner viewport: 0.60, 7.70, 4.42, 4.60
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.0, "left", 0.5, "half", "##" + .l4$ + "##"
    Font size: 5
    Colour: .faint$
    Text: 1.0, "right", 0.5, "half",
        ... .l4cap$

    Select inner viewport: .leftViewport, .rightViewport, 4.66, 5.48
    Axes: 0, .duration, 0, 1
    Paint rectangle: .bg$, 0, .duration, 0, 1

    Select inner viewport: .leftViewport, .rightViewport, 4.66, 5.48
    Axes: 0, .duration, 0, 1
    Colour: .grid$
    Dotted line
    Draw line: 0, 0.5, .duration, 0.5
    Solid line
    Line width: 1.2
    Colour: .ink$
    for .c from 2 to numChunks
        .t1 = min(.duration, (.c - 2) * chunkDur)
        .t2 = min(.duration, (.c - 1) * chunkDur)
        Draw line: .t1, abAtaxy[.c - 1], .t2, abAtaxy[.c]
    endfor

    Select inner viewport: .leftViewport, .rightViewport, 4.66, 5.48
    Axes: 0, .duration, 0, 1
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 5
    Marks left every: 1, 0.25, "yes", "yes", "no"
    Marks bottom every: 1, .tTick, "yes", "yes", "no"
    Font size: 6
    Text left: "yes", .lAtaxy$

    # =======================================================================
    # V. THE SOUND ITSELF
    # =======================================================================
    Select inner viewport: 0.60, 7.70, 5.74, 5.92
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.0, "left", 0.5, "half", "##" + .l5$ + "##"
    Font size: 5
    Colour: .faint$
    Text: 1.0, "right", 0.5, "half",
        ... .lMeasDom$ + "  —  " + .l5cap$

    .specStep = max(0.03, .duration / 1400)
    selectObject: outputID
    .spec = To Spectrogram: 0.04, max_frequency_Hz, .specStep, 20, "Gaussian"

    Select inner viewport: .leftViewport, .rightViewport, 5.98, 6.76
    selectObject: .spec
    Paint: 0, 0, 0, max_frequency_Hz, 100, 1, 50, 6, 0, 0

    Select inner viewport: .leftViewport, .rightViewport, 5.98, 6.76
    Axes: 0, .duration, 0, max_frequency_Hz
    Line width: 1.0
    for .lay to number_of_layers
        if (.lay mod 3) = 1
            Colour: .model1$
        elsif (.lay mod 3) = 2
            Colour: .model2$
        else
            Colour: .model3$
        endif
        for .chunk from 2 to numChunks
            .i1 = (.lay - 1) * numChunks + .chunk - 1
            .i2 = (.lay - 1) * numChunks + .chunk
            .f1 = cfHist#[.i1]
            .f2 = cfHist#[.i2]
            if .f1 > 0 and .f2 > 0
                .t1 = min(.duration, max(0, (.chunk - 1.5) * chunkDur))
                .t2 = min(.duration, max(0, (.chunk - 0.5) * chunkDur))
                Draw line: .t1, .f1, .t2, .f2
            endif
        endfor
    endfor
    removeObject: .spec

    Select inner viewport: .leftViewport, .rightViewport, 5.98, 6.76
    Axes: 0, .duration, 0, max_frequency_Hz
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 5
    Marks left: 5, "yes", "yes", "no"
    Marks bottom every: 1, .tTick, "yes", "yes", "no"
    Font size: 6
    Text left: "yes", .lFreq$
    Text bottom: "yes", .lTime$

    # =======================================================================
    # SUMMARY / QC
    # =======================================================================
    if normalize_output
        .norm$ = .lNorm$
    else
        .norm$ = .lRaw$
    endif

    if abDiag <> undefined
        .diag$ = fixed$(abDiag, 3)
    else
        .diag$ = "n/a"
    endif

    Select inner viewport: 0.60, 7.70, 7.16, 7.70
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Select inner viewport: 0.60, 7.70, 7.16, 7.70
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.80, "half",
        ... .lField$ + fixed$(globalCfMin, 0) + "-" + fixed$(globalCfMax, 0)
        ... + .lBw$ + fixed$(globalBwMin, 0) + "-" + fixed$(globalBwMax, 0)
        ... + .lAmp$ + fixed$(globalAmpMin, 2) + "-" + fixed$(globalAmpMax, 2)
        ... + .lRefl$ + string$(boundaryEvents)
    Text: 0.02, "left", 0.50, "half",
        ... .lCtrl$ + fixed$(spectral_drift_rate, 2)
        ... + .lBwVar$ + fixed$(bandwidth_variation, 2)
        ... + .lTurb$ + fixed$(amplitude_turbulence, 2)
        ... + .lXfade$ + fixed$(crossfadeDur * 1000, 0)
        ... + .lSelf$ + .diag$
    Text: 0.02, "left", 0.20, "half",
        ... .lOut$ + string$(number_of_layers) + .lLayers2$
        ... + string$(filterCalls) + .lStates$ + fixed$(finalPeak, 3)
        ... + .lRms$ + fixed$(finalRMS, 4) + "  |  " + .norm$
        ... + .lDisc$

    Select inner viewport: 0.60, 7.70, 7.16, 7.70
    Axes: 0, 1, 0, 1
    Colour: "{0.52, 0.52, 0.54}"
    Line width: 1
    Draw rectangle: 0, 1, 0, 1

    Select inner viewport: 0.60, 7.70, 7.76, 7.92
    Axes: 0, 1, 0, 1
    Font size: 5
    Colour: "{0.42, 0.42, 0.42}"
    Text: 0.0, "left", 0.5, "half", .lNote$

    Colour: "Black"
    Line width: 1
    Font size: 10
endproc

# ---------------------------------------------------------------------------
# Build the screen for one control state: energy per frequency x intensity
# cell. Frequency cells are log-spaced; a layer's band is distributed across
# the cells it overlaps, and its intensity row is set by its amplitude state.
# ---------------------------------------------------------------------------
procedure buildScreen: .c
    abScreenId = .c
    for .i to abNF
        for .j to abNG
            abCell[.i, .j] = 0
        endfor
    endfor
    abCellTot = 0

    for .lay to number_of_layers
        .idx = (.lay - 1) * numChunks + .c
        .cf = cfHist#[.idx]
        .bwv = bwHist#[.idx]
        .amp = ampHist#[.idx]

        if .cf > 0 and .amp > 0
            .lo = ln(max(min_frequency_Hz, .cf - 0.5 * .bwv))
            .hi = ln(min(max_frequency_Hz, .cf + 0.5 * .bwv))
            .gdb = 20 * log10(.amp)
            .g = ceiling((.gdb - abGminDb) / (0 - abGminDb) * abNG)
            .g = max(1, min(abNG, .g))

            if .hi > .lo
                .enr = .amp * .amp
                for .i to abNF
                    .fa = abLogMin + (.i - 1) / abNF * abLogSpan
                    .fb = abLogMin + .i / abNF * abLogSpan
                    .ov = min(.hi, .fb) - max(.lo, .fa)
                    if .ov > 0
                        .share = .enr * .ov / (.hi - .lo)
                        abCell[.i, .g] = abCell[.i, .g] + .share
                        abCellTot = abCellTot + .share
                    endif
                endfor
            endif
        endif
    endfor
endproc

# ---------------------------------------------------------------------------
# Paint the current screen into a rectangle of the CURRENT world coordinates.
# Grains are drawn as dots so the figure reads as a population rather than a
# heat map, which is how Xenakis drew screens.
# ---------------------------------------------------------------------------
procedure paintScreen: .x0, .x1, .y0, .y1, .dotMm, .maxDots
    Line width: 0.5
    Colour: "{0.72, 0.72, 0.76}"
    for .i from 1 to abNF - 1
        .x = .x0 + (.x1 - .x0) * .i / abNF
        Draw line: .x, .y0, .x, .y1
    endfor
    for .j from 1 to abNG - 1
        .y = .y0 + (.y1 - .y0) * .j / abNG
        Draw line: .x0, .y, .x1, .y
    endfor

    for .i to abNF
        for .j to abNG
            # A cell holding real energy must not round down to nothing, or
            # the reader sees "no energy here" where the truth is "a little".
            if abCellTot > 0
                .n = round(.maxDots * abCell[.i, .j] / abCellTot)
                if .n < 1 and abCell[.i, .j] > 0
                    .n = 1
                endif
            else
                .n = 0
            endif
            .ca = .x0 + (.x1 - .x0) * (.i - 1) / abNF
            .cb = .x0 + (.x1 - .x0) * .i / abNF
            .cc = .y0 + (.y1 - .y0) * (.j - 1) / abNG
            .cd = .y0 + (.y1 - .y0) * .j / abNG
            # Deterministic placement. randomUniform would make the figure a
            # function of the draw call rather than of the data: the same seed
            # and the same Sound would produce a different picture each time.
            # This hash depends only on (screen, cell, dot index).
            for .k to .n
                .hx = sin(.k * 12.9898 + .i * 78.233 + .j * 37.719
                    ... + abScreenId * 4.1414) * 43758.5453
                .hy = sin(.k * 39.3468 + .i * 11.135 + .j * 83.155
                    ... + abScreenId * 7.7717) * 24634.6345
                .ux = .hx - floor(.hx)
                .uy = .hy - floor(.hy)
                .px = .ca + (.cb - .ca) * (0.14 + 0.72 * .ux)
                .py = .cc + (.cd - .cc) * (0.14 + 0.72 * .uy)
                Paint circle (mm): "{0.15, 0.15, 0.17}", .px, .py, .dotMm
            endfor
        endfor
    endfor

    Colour: "{0.15, 0.15, 0.17}"
    Line width: 1
    Draw rectangle: .x0, .x1, .y0, .y1
endproc
