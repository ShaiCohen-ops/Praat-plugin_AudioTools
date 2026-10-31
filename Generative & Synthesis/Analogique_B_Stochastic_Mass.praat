# ============================================================
# Praat AudioTools - Analogique_B_Stochastic_Mass.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 3.1 (2026)
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
# v3.1 (review round on v3.0):
#   - Default Duration 0.5 min (was 7): a 7-minute render is ~360 000 grains.
#     Measured cost is ~0.37 ms per grain (Praat 6.4, one Formula (part) per
#     grain): 30 s renders in ~10 s, the 149.5 s section plan in ~50 s,
#     7 min in ~2.5 min. Kept as is: every grain stays exact.
#   - Screen identity: the g/d-to-f pairing is drawn once per STATE for the
#     whole render instead of per screen, so each recurrence of A is the
#     same ten-stream cloud.
#   - Grain count per stream is the target density x 0.5 s with stochastic
#     rounding of the fraction (Arcella & Silvestri: count set by the density
#     region), replacing Poisson counts. Onsets stay uniform in the screen.
#   - Figure: panels I and II now plot EVERY grain at its own frequency
#     (log-proportional inside its region column) and phon, instead of a
#     dot count per cell placed by hash. The caption's claim is now literal.
#   - Form: the Duration comment says which engines use which fields; the
#     section-plan option says it ignores Duration.
#
# v3.0: MARKOVIAN GRANULAR ENGINE ADDED (Engine menu).
#   The noise engine is kept unchanged as engine 1, "Stochastic Filter Mass":
#   a free tool in the spirit of Xenakis, NOT his method (Gaussian walk
#   driving filtered noise). Engines 2 and 3 implement Analogique B's own
#   mechanism, forward from the published data:
#   - Screens A-H = combinations of frequency set f0/f1, intensity set g0/g1,
#     density set d0/d1 (A = f0 g0 d0 ... H = f1 g1 d1).
#   - The next screen is drawn from the 8x8 MTPZ of Formalized Music, ch. III,
#     p. 89. The book prints NEXT state in rows, CURRENT in columns (columns
#     sum to 1); it is stored transposed. F,D = 0.114 per Xenakis (one
#     secondary source prints 0.144, which breaks the column sum). Arcella &
#     Silvestri's prose reverses the direction of the A/B example; the
#     formal definition gives P(next A | current B) = 0.357.
#   - Each 0.5 s screen holds TEN grain streams. The ten-entry pools (with
#     duplicates) give each stream a frequency region (16 regions, 42 Hz to
#     11.4 kHz), an intensity region (4 phon regions, 50-90) and a density
#     (1.3 to 315.9 grains/s; density 7 = 957.7 is defined but unused).
#   - Grains: 40 ms sine, onsets a Poisson process per stream, frequency
#     uniform in the region, random phase.
#   - The whole screen and grain table is generated BEFORE rendering; each
#     grain is then written exactly into its own window (Formula (part)).
#   - Engine 2: free chain from A for Duration. Engine 3: Ciamarone's
#     reported ten-segment plan (149.5 s): equilibrium = the chain;
#     perturbation = the named screen held, after Arcella & Silvestri's
#     reading of 15-20 s as 10 x one screen. Segment 1 uses their printed
#     30 screens. Sources DISAGREE at 15-20 s (Ciamarone C, Arcella &
#     Silvestri A) and Ciamarone's segment 6 reads "A or C": C and A are
#     used respectively, and both are flagged in the Info window. The plan
#     is reported data, NOT a validated reconstruction of the tape.
#   - MODELLING CHOICES, flagged in figure and Info: g and d entries paired
#     with the f streams by a random permutation per screen (the pools do
#     not give the pairing); phon converted to level by A-weighting (an
#     approximation of the equal-loudness contours, 90 phon = 0 dB before
#     normalisation); 3 ms grain edges (rectangular in theory, smoothed in
#     the recordings); mono output (the original is four-track).
#   - New figure for engines 2-3, in the same vocabulary but every mark is
#     real: screens dotted with the grains actually rendered, the prescribed
#     matrix with the observed transition frequencies beside it, the screen
#     sequence with perturbations shaded, and the measured spectrogram.
#   - Info window: screen sequence per segment, occupancy against the
#     chain's stationary distribution, matrix row-sum check.
#   - Engine 1 output is bit-identical to v2.4.1 for the same seed.
#   - FLAGGED (Praat bug, not this script): on Praat 6.x a fixed seed does
#     NOT reproduce engine 1 when an earlier run in the same session left
#     a cached spare in randomGauss (Box-Muller); reseeding does not clear
#     it. Separate sessions, and Praat 7.0, are reproducible. Engines 2-3
#     use no Gaussian draws and reproduce on every version.
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

form Analogique B - Stochastic Sound Mass v3.1
    optionmenu Engine 1
        option Stochastic Filter Mass (free, Xenakis-inspired)
        option Analogique B - Markov chain (Duration)
        option Analogique B - section plan (149.5 s, ignores Duration)
    comment === Morphology preset (Stochastic Filter Mass) ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Balanced Mass
        option Slow Narrow Drift
        option Migrating Bands
        option Turbulent Wide Cloud
        option Low Dark Mass
        option High Spectral Haze
        option Sparse Streams

    comment === Duration: engines 1-2 | layers ... turbulence: engine 1 only ===
    positive Duration_minutes 0.5
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
if engine = 1 and filterCalls > 50000
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
writeInfoLine: "  ANALOGIQUE B - STOCHASTIC SOUND MASS v3.1"
writeInfoLine: "  Xenakis-inspired statistical mass model"
writeInfoLine: "=============================================="
appendInfoLine: ""
if engine = 1
    appendInfoLine: "Engine: Stochastic Filter Mass (free; not Xenakis's method)"
elsif engine = 2
    appendInfoLine: "Engine: Analogique B, Markovian sine-grain screens, free chain"
else
    appendInfoLine: "Engine: Analogique B, Markovian sine-grain screens, Ciamarone section plan"
endif
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Duration: ", fixed$(duration_s / 60, 2), " minutes"
appendInfoLine: "Layers: ", number_of_layers
appendInfoLine: "Spectral range: ", fixed$(min_frequency_Hz, 0), " - ", fixed$(max_frequency_Hz, 0), " Hz"
appendInfoLine: "Control state: ", fixed$(chunkDur, 2), " s | equal-power compensated overlap: ", fixed$(crossfadeDur * 1000, 0), " ms"
appendInfoLine: "Randomness: ", seedLabel$
appendInfoLine: "Mode: ", modeStr$
appendInfoLine: ""

if engine = 1
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
else
    # Markovian granular Analogique B (see abMarkovGenerate).
    if random_seed > 0
        random_initializeWithSeedUnsafelyButPredictably (random_seed)
    endif
    @abMarkovGenerate
    if seedWasFixed
        random_initializeSafelyAndUnpredictably ()
    endif
    selectObject: outputID
endif

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
    if engine = 1
        @drawMassFigure: finalDur
    else
        @drawMarkovFigure: finalDur
    endif
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
if engine = 1
    appendInfoLine: "Filter calls: ", filterCalls
    appendInfoLine: "Boundary reflections: ", boundaryEvents
endif
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

    Font size: 5
    Select inner viewport: 1.10, 3.85, 2.78, 4.00
    Axes: 0, 1, 0, 1
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

    Font size: 4
    Select inner viewport: 4.70, 6.90, 2.78, 4.00
    Axes: 0, abNR, 0, abNR
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

    Font size: 5
    Select inner viewport: 4.70, 6.90, 2.78, 4.00
    Axes: 0, abNR, 0, abNR
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


# ===========================================================================
# ===========================================================================
# ANALOGIQUE B - MARKOVIAN GRANULAR ENGINE (engines 2 and 3)
#
# Sources (data embedded below, no external file):
#   Xenakis, Formalized Music (1992), ch. III, p. 89: the 8x8 MTPZ matrix of
#     screens A-H (shared by Analogique A and B). Published with NEXT state
#     in rows and CURRENT state in columns; every column sums to 1. Stored
#     here transposed, abMz[current, next], so every ROW sums to 1.
#     Row F / column D = 0.114 (Xenakis); one secondary source prints 0.144,
#     which breaks the column total.
#   Arcella & Silvestri (2012), Analogique B: A Computer Model of the
#     Compositional Process: the 16 frequency regions, 4 intensity regions
#     (phon), 7 densities (grains/s), the ten-entry weighted pools f0/f1,
#     g0/g1, d0/d1, ten grain streams per screen, 40 ms sine grains, 0.5 s
#     screens, and the printed first 30 screens.
#   Ciamarone (2012), Towards a Real-Time Implementation of Analogique B:
#     the reported ten-segment plan (equilibrium / perturbation).
# ===========================================================================

procedure abParse: .s$
    abListN = 0
    .s$ = .s$ + " "
    while length(.s$) > 0
        .sp = index(.s$, " ")
        .tok$ = left$(.s$, .sp - 1)
        .s$ = mid$(.s$, .sp + 1, length(.s$) - .sp)
        if .tok$ <> ""
            abListN = abListN + 1
            abList[abListN] = number(.tok$)
        endif
    endwhile
endproc

procedure abLoadData
    abStateName$[1] = "A"
    abStateName$[2] = "B"
    abStateName$[3] = "C"
    abStateName$[4] = "D"
    abStateName$[5] = "E"
    abStateName$[6] = "F"
    abStateName$[7] = "G"
    abStateName$[8] = "H"
    # MTPZ, current state in rows, next state in columns.
    @abParse: "0.021 0.084 0.084 0.336 0.019 0.076 0.076 0.304 "
        ... + "0.357 0.089 0.323 0.081 0.063 0.016 0.057 0.014 "
        ... + "0.084 0.076 0.021 0.019 0.336 0.304 0.084 0.076 "
        ... + "0.189 0.126 0.126 0.084 0.171 0.114 0.114 0.076 "
        ... + "0.165 0.150 0.150 0.135 0.110 0.100 0.100 0.090 "
        ... + "0.204 0.136 0.036 0.024 0.306 0.204 0.054 0.036 "
        ... + "0.408 0.072 0.272 0.048 0.102 0.018 0.068 0.012 "
        ... + "0.096 0.144 0.144 0.216 0.064 0.096 0.096 0.144"
    abMzMaxDev = 0
    for .a to 8
        .sum = 0
        for .b to 8
            abMz[.a, .b] = abList[(.a - 1) * 8 + .b]
            .sum = .sum + abMz[.a, .b]
        endfor
        abMzRowSum[.a] = .sum
        abMzMaxDev = max(abMzMaxDev, abs(.sum - 1))
    endfor
    # Screens: A f0 g0 d0, B f0 g0 d1, C f0 g1 d0, D f0 g1 d1,
    #          E f1 g0 d0, F f1 g0 d1, G f1 g1 d0, H f1 g1 d1.
    for .s to 8
        abScrF[.s] = floor((.s - 1) / 4)
        abScrG[.s] = floor((.s - 1) / 2) mod 2
        abScrD[.s] = (.s - 1) mod 2
    endfor
    # 16 frequency regions (Hz).
    @abParse: "42 63 84 131 178 267 355 532 710 1065 1420 2130 2850 4275 5700 8550 11400"
    for .r to 16
        abFLo[.r] = abList[.r]
        abFHi[.r] = abList[.r + 1]
    endfor
    # 4 intensity regions (phon): 50-60, 60-70, 70-80, 80-90.
    for .r to 4
        abPhLo[.r] = 40 + 10 * .r
    endfor
    # 7 densities (grains per second); 7 is defined but in neither pool.
    @abParse: "1.3 3.9 11.7 35.1 105.4 315.9 957.7"
    for .r to 7
        abDens[.r] = abList[.r]
    endfor
    # Ten-entry weighted pools, duplicates kept on purpose.
    @abParse: "1 2 3 5 7 10 13 14 15 16"
    for .k to 10
        abPoolF[0, .k] = abList[.k]
    endfor
    @abParse: "4 6 6 8 9 9 11 11 12 12"
    for .k to 10
        abPoolF[1, .k] = abList[.k]
    endfor
    @abParse: "1 1 1 1 2 2 3 3 4 4"
    for .k to 10
        abPoolG[0, .k] = abList[.k]
    endfor
    @abParse: "1 1 1 2 2 2 3 3 4 4"
    for .k to 10
        abPoolG[1, .k] = abList[.k]
    endfor
    @abParse: "1 1 1 2 3 3 4 5 6 6"
    for .k to 10
        abPoolD[0, .k] = abList[.k]
    endfor
    @abParse: "1 2 2 2 4 4 5 5 6 6"
    for .k to 10
        abPoolD[1, .k] = abList[.k]
    endfor
    # Stationary distribution of the chain, for the occupancy check.
    for .a to 8
        abStat[.a] = 1 / 8
    endfor
    for .it to 500
        for .b to 8
            .acc = 0
            for .a to 8
                .acc = .acc + abStat[.a] * abMz[.a, .b]
            endfor
            .tmp[.b] = .acc
        endfor
        for .b to 8
            abStat[.b] = .tmp[.b]
        endfor
    endfor
endproc

# Draw the next screen from row `.cur` of the matrix.
procedure abNextScreen: .cur
    .u = randomUniform(0, 1)
    .acc = 0
    .next = 8
    .found = 0
    for .b to 8
        .acc = .acc + abMz[.cur, .b]
        if .found = 0 and .u < .acc
            .next = .b
            .found = 1
        endif
    endfor
endproc

# A-weighting in dB (IEC 61672); used to turn phon into a level.
procedure abAWeight: .f
    .f2 = .f * .f
    .ra = (12194 ^ 2) * .f2 * .f2 / ((.f2 + 20.6 ^ 2) * sqrt((.f2 + 107.7 ^ 2) * (.f2 + 737.9 ^ 2)) * (.f2 + 12194 ^ 2))
    .db = 20 * log10(.ra) + 2.00
endproc

procedure abAddScreen: .state, .mode, .seg, .sampled
    abNScr = abNScr + 1
    abScr[abNScr] = .state
    abScrMode[abNScr] = .mode
    abScrSeg[abNScr] = .seg
    abScrSampled[abNScr] = .sampled
endproc

# ---------------------------------------------------------------------------
# Build the screen sequence, then the grain table, then render.
# ---------------------------------------------------------------------------
procedure abMarkovGenerate
    abScreenDur = 0.5
    abGrainDur = 0.04
    abEdge = 0.003
    @abLoadData

    # ----- 1. SCREEN SEQUENCE ------------------------------------------------
    abNScr = 0
    abNSeg = 0
    if engine = 2
        # Free chain in equilibrium from screen A for the requested duration.
        abNSeg = 1
        abSegLen[1] = round(duration_s / abScreenDur) * abScreenDur
        abSegMode[1] = 0
        abSegHeld[1] = 0
        abSegNote$[1] = "free chain from A"
        .nScr = max(2, round(duration_s / abScreenDur))
        @abAddScreen: 1, 0, 1, 0
        for .k from 2 to .nScr
            @abNextScreen: abScr[abNScr]
            @abAddScreen: abNextScreen.next, 0, 1, 1
        endfor
    else
        # Ciamarone's ten-segment plan. Equilibrium = the chain; perturbation
        # = the named screen held (Arcella & Silvestri's reading of 15-20 s
        # as 10 x one screen). Segment 1 uses the 30 screens Arcella &
        # Silvestri print for 0-15 s instead of a fresh draw.
        @abParse: "15 0 0  5 1 3  12 0 0  4 0 0  7 0 0  36 1 1  22 1 2  15 0 0  18.5 0 0  15 1 4"
        abNSeg = abListN / 3
        for .g to abNSeg
            abSegLen[.g] = abList[3 * .g - 2]
            abSegMode[.g] = abList[3 * .g - 1]
            abSegHeld[.g] = abList[3 * .g]
            abSegNote$[.g] = ""
        endfor
        abSegNote$[1] = "screens as printed by Arcella & Silvestri"
        abSegNote$[2] = "C after Ciamarone; Arcella & Silvestri hear 10 x A here"
        abSegNote$[6] = "Ciamarone: A or C; A used here"
        @abParse: "1 4 6 6 5 3 4 4 4 3 6 6 6 2 4 7 3 8 3 3 8 4 5 4 6 6 5 3 5 2"
        abPrinted = abListN
        for .k to abPrinted
            abPrint[.k] = abList[.k]
        endfor
        for .g to abNSeg
            .n = round(abSegLen[.g] / abScreenDur)
            for .k to .n
                if .g = 1
                    @abAddScreen: abPrint[.k], 0, .g, 0
                elsif abSegMode[.g] = 1
                    @abAddScreen: abSegHeld[.g], 1, .g, 0
                else
                    @abNextScreen: abScr[abNScr]
                    @abAddScreen: abNextScreen.next, 0, .g, 1
                endif
            endfor
        endfor
    endif
    duration_s = abNScr * abScreenDur + abGrainDur + 0.05

    # Occupancy and transitions actually drawn from the matrix.
    for .a to 8
        abOcc[.a] = 0
        abOccEq[.a] = 0
        abObsRow[.a] = 0
        for .b to 8
            abObs[.a, .b] = 0
        endfor
    endfor
    abNSampled = 0
    for .k to abNScr
        abOcc[abScr[.k]] = abOcc[abScr[.k]] + 1
        if abScrSampled[.k]
            abOccEq[abScr[.k]] = abOccEq[abScr[.k]] + 1
            .a = abScr[.k - 1]
            .b = abScr[.k]
            abObs[.a, .b] = abObs[.a, .b] + 1
            abObsRow[.a] = abObsRow[.a] + 1
            abNSampled = abNSampled + 1
        endif
    endfor

    # ----- 2. STREAMS: ten per screen ---------------------------------------
    # The pools give each screen ten (frequency, intensity, density) regions,
    # but not which g and d entries belong with which f entry. The pairing is
    # drawn ONCE PER STATE for the whole render, so a screen keeps its
    # identity: every occurrence of A is the same ten-stream cloud. (The
    # pairing itself is still a modelling choice; Ciamarone's worked screen-A
    # mapping was not available to this implementation.)
    for .s to 8
        for .j to 10
            abPermG[.s, .j] = .j
            abPermD[.s, .j] = .j
        endfor
        for .i from 1 to 9
            .r = randomInteger(.i, 10)
            .tmp = abPermG[.s, .i]
            abPermG[.s, .i] = abPermG[.s, .r]
            abPermG[.s, .r] = .tmp
            .r = randomInteger(.i, 10)
            .tmp = abPermD[.s, .i]
            abPermD[.s, .i] = abPermD[.s, .r]
            abPermD[.s, .r] = .tmp
        endfor
    endfor
    # Grain count per stream = the region's TARGET density over the screen
    # (density x 0.5 s), as in Arcella & Silvestri, with the fractional part
    # rounded stochastically so the long-run density is exact (1.3/s gives
    # 0.65 grain per screen: 1 grain 65% of the time, else none).
    abNGrain = 0
    for .k to abNScr
        .s = abScr[.k]
        for .j to 10
            .q = (.k - 1) * 10 + .j
            abStF[.q] = abPoolF[abScrF[.s], .j]
            abStG[.q] = abPoolG[abScrG[.s], abPermG[.s, .j]]
            abStD[.q] = abPoolD[abScrD[.s], abPermD[.s, .j]]
            .mean = abDens[abStD[.q]] * abScreenDur
            abStN[.q] = floor(.mean)
            if randomUniform(0, 1) < .mean - floor(.mean)
                abStN[.q] = abStN[.q] + 1
            endif
            abNGrain = abNGrain + abStN[.q]
        endfor
    endfor

    # ----- 3. GRAIN TABLE ---------------------------------------------------
    gT# = zero#(abNGrain)
    gF# = zero#(abNGrain)
    gA# = zero#(abNGrain)
    gPh# = zero#(abNGrain)
    gPhon# = zero#(abNGrain)
    gScr# = zero#(abNGrain)
    gFR# = zero#(abNGrain)
    gGR# = zero#(abNGrain)
    .n = 0
    for .k to abNScr
        abScrFirst[.k] = .n + 1
        for .j to 10
            .q = (.k - 1) * 10 + .j
            for .c to abStN[.q]
                .n = .n + 1
                .fr = abStF[.q]
                .gr = abStG[.q]
                # onset uniform within the screen
                gT#[.n] = (.k - 1) * abScreenDur + randomUniform(0, abScreenDur)
                gF#[.n] = randomUniform(abFLo[.fr], abFHi[.fr])
                gPhon#[.n] = randomUniform(abPhLo[.gr], abPhLo[.gr] + 10)
                # Phon -> level: phon minus A-weighting approximates the
                # equal-loudness contour; 90 phon = 0 dB before normalisation.
                @abAWeight: gF#[.n]
                gA#[.n] = 10 ^ ((gPhon#[.n] - 90 - abAWeight.db) / 20)
                gPh#[.n] = randomUniform(0, 2 * pi)
                gScr#[.n] = .k
                gFR#[.n] = .fr
                gGR#[.n] = .gr
            endfor
        endfor
        abScrLast[.k] = .n
    endfor

    appendInfoLine: "Stage 1: ", abNScr, " screens, ", abNGrain, " sine grains (", fixed$(abNGrain / (abNScr * abScreenDur), 0), " per second)"

    # ----- 4. RENDER: every grain written into its own 40 ms window ----------
    appendInfoLine: "Stage 2: Rendering grains..."
    outputID = Create Sound from formula: "ab_grains", 1, 0, duration_s, sampleRate, "0"
    for .i to abNGrain
        .t$ = fixed$(gT#[.i], 7)
        .t1$ = fixed$(gT#[.i] + abGrainDur, 7)
        Formula (part): gT#[.i], gT#[.i] + abGrainDur, 1, 1,
            ... "self + " + string$(gA#[.i]) + " * min(1, (x - " + .t$ + ")/" + string$(abEdge)
            ... + ", (" + .t1$ + " - x)/" + string$(abEdge) + ") * sin("
            ... + fixed$(2 * pi * gF#[.i], 5) + " * (x - " + .t$ + ") + " + fixed$(gPh#[.i], 5) + ")"
        if (.i mod 20000) = 0
            appendInfoLine: "  ", .i, " / ", abNGrain
        endif
    endfor
    if normalize_output
        Scale peak: 0.90
    endif
    if engine = 2
        Rename: "analogique_b_markov_" + fixed$(duration_s, 0) + "s"
    else
        Rename: "analogique_b_section_plan"
    endif

    # ----- 5. REPORT ---------------------------------------------------------
    appendInfoLine: ""
    appendInfoLine: "Matrix (Formalized Music p. 89): max |row sum - 1| = ", fixed$(abMzMaxDev, 6)
    appendInfoLine: "Screen sequence by segment (P = perturbation, screen held):"
    .k0 = 1
    for .g to abNSeg
        .line$ = ""
        for .k from .k0 to abNScr
            if abScrSeg[.k] = .g
                .line$ = .line$ + abStateName$[abScr[.k]]
                .k1 = .k
            endif
        endfor
        if abSegMode[.g] = 1
            .md$ = "P"
        else
            .md$ = "E"
        endif
        appendInfoLine: "  ", .g, " ", .md$, " ", fixed$(abSegLen[.g], 1), " s  ", .line$
        if abSegNote$[.g] <> ""
            appendInfoLine: "        (", abSegNote$[.g], ")"
        endif
        .k0 = .k1 + 1
    endfor
    appendInfoLine: ""
    appendInfoLine: "Occupancy of the screens DRAWN from the matrix vs its stationary distribution"
    appendInfoLine: "(held perturbation screens and printed screens excluded; all screens in brackets):"
    for .a to 8
        appendInfoLine: "  ", abStateName$[.a], "  ", fixed$(abOccEq[.a] / max(1, abNSampled), 3),
            ... "  stationary ", fixed$(abStat[.a], 3), "  [all ", fixed$(abOcc[.a] / abNScr, 3), "]"
    endfor
    appendInfoLine: "  Transitions drawn from the matrix: ", abNSampled
    appendInfoLine: ""
    appendInfoLine: "Fidelity:"
    appendInfoLine: "  Sourced: matrix, screens A-H, 16 Hz regions, phon regions, densities,"
    appendInfoLine: "    ten-entry weighted pools, ten streams per screen, 40 ms grains, 0.5 s screens."
    appendInfoLine: "  Modelling choices: g/d paired to f streams by a random permutation drawn once"
    appendInfoLine: "    per state (screens keep their identity); grain count = target density x 0.5 s,"
    appendInfoLine: "    fraction rounded stochastically; onsets uniform in the screen; frequency"
    appendInfoLine: "    uniform in Hz inside a region; phon -> level by"
    appendInfoLine: "    A-weighting (90 phon = 0 dB); 3 ms grain edges (rectangular in theory);"
    appendInfoLine: "    mono, not four-track."
    if engine = 3
        appendInfoLine: "  Section plan: reported by Ciamarone, not a validated reconstruction;"
        appendInfoLine: "    perturbation modelled as the named screen held."
    endif
endproc

# ===========================================================================
# FIGURE FOR THE MARKOVIAN ENGINE: every mark is an actual grain or screen.
# ===========================================================================
# Plot every grain of screen .k at its own frequency and phon. x runs over
# the 16 regions as equal columns (so the grid is the region grid), with
# each grain placed log-proportionally inside its region; y is phon 50-90.
procedure abPaintGrains: .k, .x0, .x1, .y0, .y1, .dotMm
    Line width: 1
    Colour: "{0.82, 0.82, 0.85}"
    for .i from 1 to 15
        .x = .x0 + (.x1 - .x0) * .i / 16
        Draw line: .x, .y0, .x, .y1
    endfor
    for .j from 1 to 3
        .y = .y0 + (.y1 - .y0) * .j / 4
        Draw line: .x0, .y, .x1, .y
    endfor
    for .n from abScrFirst[.k] to abScrLast[.k]
        .r = gFR#[.n]
        .u = (ln(gF#[.n]) - ln(abFLo[.r])) / (ln(abFHi[.r]) - ln(abFLo[.r]))
        .px = .x0 + (.x1 - .x0) * (.r - 1 + .u) / 16
        .py = .y0 + (.y1 - .y0) * (gPhon#[.n] - 50) / 40
        Paint circle (mm): "{0.15, 0.15, 0.17}", .px, .py, .dotMm
    endfor
    Colour: "{0.15, 0.15, 0.17}"
    Draw rectangle: .x0, .x1, .y0, .y1
endproc

procedure abBuildGrainScreen: .k
    abScreenId = .k
    for .i to abNF
        for .j to abNG
            abCell[.i, .j] = 0
        endfor
    endfor
    abCellTot = 0
    for .n from abScrFirst[.k] to abScrLast[.k]
        abCell[gFR#[.n], gGR#[.n]] = abCell[gFR#[.n], gGR#[.n]] + 1
        abCellTot = abCellTot + 1
    endfor
endproc

procedure drawMarkovFigure: .duration
    .left = 0.90
    .right = 7.70
    .ink$ = "{0.15, 0.15, 0.17}"
    .grid$ = "{0.62, 0.62, 0.66}"
    .faint$ = "{0.45, 0.45, 0.52}"
    .bg$ = "{0.975, 0.975, 0.978}"
    .pert$ = "{0.93, 0.88, 0.80}"
    abNF = 16
    abNG = 4

    if .duration <= 30
        .tTick = 5
    elsif .duration <= 120
        .tTick = 20
    else
        .tTick = 30
    endif

    if figure_language = 2
        .lTitle$ = "ANALOGIQUE B  —  ÉCRANS MARKOVIENS"
        .lGloss$ = "chaque point est un grain sinusoïdal réellement produit ; les écrans suivent la matrice de Musiques formelles"
        .l1$ = "I  LE LIVRE D'ÉCRANS"
        .l1cap$ = "16 régions de fréquence × 4 régions d'intensité (phone) ; chaque grain de l'écran à sa fréquence et à son niveau"
        .l2$ = "II  UN ÉCRAN"
        .l2at$ = "écran "
        .lF$ = "F   régions de fréquence (Hz)"
        .lG$ = "G   intensité (phone)"
        .l3$ = "III  MATRICE MTPZ (Xenakis, p. 89)"
        .l3cap$ = "ligne = écran actuel, colonne = suivant ; teinte et chiffre = probabilité prescrite, petit chiffre gris = fréquence observée"
        .l4$ = "IV  LA SUITE DES ÉCRANS"
        .l4cap$ = "écran par demi-seconde ; fond coloré = perturbation (écran tenu)"
        .l5$ = "V  LE SON LUI-MÊME"
        .l5cap$ = "spectrogramme mesuré"
        .lFreq$ = "Fréquence (Hz)"
        .lTime$ = "Temps (s)"
        .lScreens$ = " écrans"
        .lGrains$ = " grains"
        .lNote$ = "Données : Xenakis, Musiques formelles p. 89 (matrice) ; Arcella & Silvestri 2012 (régions, réservoirs) ; Ciamarone 2012 (plan). L'appariement g/d (fixe par état), le placement des attaques et la conversion phone → niveau sont des choix de modélisation."
    else
        .lTitle$ = "ANALOGIQUE B  —  MARKOVIAN SCREENS"
        .lGloss$ = "every dot is a sine grain actually rendered; screens follow the matrix of Formalized Music"
        .l1$ = "I  THE BOOK OF SCREENS"
        .l1cap$ = "16 frequency regions × 4 intensity regions (phon); every grain of the screen at its own frequency and phon"
        .l2$ = "II  ONE SCREEN"
        .l2at$ = "screen "
        .lF$ = "F   frequency regions (Hz)"
        .lG$ = "G   intensity (phon)"
        .l3$ = "III  MTPZ MATRIX (Xenakis, p. 89)"
        .l3cap$ = "row = current screen, column = next; shade and figure = prescribed probability, small grey = observed frequency"
        .l4$ = "IV  THE SEQUENCE OF SCREENS"
        .l4cap$ = "one screen per half second; tinted background = perturbation (screen held)"
        .l5$ = "V  THE SOUND ITSELF"
        .l5cap$ = "measured spectrogram"
        .lFreq$ = "Frequency (Hz)"
        .lTime$ = "Time (s)"
        .lScreens$ = " screens"
        .lGrains$ = " grains"
        .lNote$ = "Data: Xenakis, Formalized Music p. 89 (matrix); Arcella & Silvestri 2012 (regions, pools); Ciamarone 2012 (plan). Pairing of g/d to f streams (fixed per state), onset placement and phon-to-level conversion are modelling choices."
    endif
    if engine = 2
        .mode$ = if figure_language = 2 then "chaîne de Markov libre" else "free Markov chain" fi
    else
        .mode$ = if figure_language = 2 then "plan des sections (Ciamarone 2012)" else "section plan (Ciamarone 2012)" fi
    endif
    if random_seed > 0
        .seed$ = "seed " + string$(random_seed)
    else
        .seed$ = "random seed"
    endif

    Erase all
    Solid line
    Line width: 1

    # ---- TITLE ----
    Select inner viewport: 0.60, 7.70, 0.12, 0.52
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.76, "half", "##" + .lTitle$ + "##"
    Font size: 6
    Colour: .faint$
    Text: 0.5, "centre", 0.28, "half",
        ... .mode$ + "  |  " + string$(abNScr) + .lScreens$ + "  |  " + string$(abNGrain) + .lGrains$
        ... + "  |  " + fixed$(.duration, 1) + " s  |  " + .seed$
    Text: 0.5, "centre", 0.04, "half", .lGloss$

    # ---- I. BOOK OF SCREENS ----
    Select inner viewport: 0.60, 7.70, 0.86, 1.04
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.0, "left", 0.5, "half", "##" + .l1$ + "##"
    Font size: 5
    Colour: .faint$
    Text: 1.0, "right", 0.5, "half", .l1cap$

    .shown = min(10, abNScr)
    Select inner viewport: 0.60, 7.70, 1.10, 1.96
    Axes: 0, .shown, 0, 1
    for .k to .shown
        if .shown > 1
            .c = round(1 + (.k - 1) * (abNScr - 1) / (.shown - 1))
        else
            .c = 1
        endif
        @abPaintGrains: .c, .k - 0.94, .k - 0.10, 0.22, 0.97, 0.20
    endfor
    Select inner viewport: 0.60, 7.70, 1.10, 1.96
    Axes: 0, .shown, 0, 1
    Font size: 5
    Colour: .faint$
    for .k to .shown
        if .shown > 1
            .c = round(1 + (.k - 1) * (abNScr - 1) / (.shown - 1))
        else
            .c = 1
        endif
        Text: .k - 0.53, "centre", 0.10, "half",
            ... abStateName$[abScr[.c]] + "  " + fixed$((.c - 1) * abScreenDur, 1) + " s"
    endfor

    # ---- II. ONE SCREEN / III. MATRIX headings ----
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

    # densest screen, so the enlarged view shows a full population
    .mid = 1
    .best = -1
    for .k to abNScr
        .cnt = abScrLast[.k] - abScrFirst[.k] + 1
        if .cnt > .best
            .best = .cnt
            .mid = .k
        endif
    endfor
    Select inner viewport: 1.10, 3.85, 2.78, 4.00
    Axes: 0, 1, 0, 1
    @abPaintGrains: .mid, 0, 1, 0, 1, 0.28
    Font size: 4
    Select inner viewport: 1.10, 3.85, 2.78, 4.00
    Axes: 0, 1, 0, 1
    Colour: .faint$
    for .r from 1 to 17
        if (.r mod 2) = 1
            if .r <= 16
                .f = abFLo[.r]
            else
                .f = abFHi[16]
            endif
            if .f >= 1000
                .lab$ = fixed$(.f / 1000, 1) + "k"
            else
                .lab$ = fixed$(.f, 0)
            endif
            Text: (.r - 1) / 16, "centre", -0.06, "half", .lab$
        endif
    endfor
    Font size: 5
    Select inner viewport: 1.10, 3.85, 2.78, 4.00
    Axes: 0, 1, 0, 1
    Colour: .faint$
    Text: 0.5, "centre", -0.16, "half", .lF$
    for .j from 0 to 4
        Text: -0.03, "right", .j / 4, "half", string$(50 + 10 * .j)
    endfor
    Text: -0.19, "centre", 0.5, "half", .lG$
    Text: 0.5, "centre", 1.08, "half",
        ... .l2at$ + abStateName$[abScr[.mid]] + "  " + fixed$((.mid - 1) * abScreenDur, 1) + " s  |  "
        ... + string$(.best) + .lGrains$

    # ---- III. MATRIX (prescribed, current rows -> next columns) ----
    Select inner viewport: 4.70, 6.90, 2.78, 4.00
    Axes: 0, 8, 0, 8
    for .a to 8
        for .b to 8
            .g = 1 - 1.6 * abMz[.a, .b]
            .g = max(0.30, .g)
            .g$ = fixed$(.g, 3)
            Paint rectangle: "{" + .g$ + ", " + .g$ + ", " + .g$ + "}", .b - 1, .b, 8 - .a, 8 - .a + 1
        endfor
    endfor
    Select inner viewport: 4.70, 6.90, 2.78, 4.00
    Axes: 0, 8, 0, 8
    Colour: .grid$
    Line width: 1
    for .i from 0 to 8
        Draw line: .i, 0, .i, 8
        Draw line: 0, .i, 8, .i
    endfor
    Colour: .ink$
    Draw rectangle: 0, 8, 0, 8
    Font size: 4
    Select inner viewport: 4.70, 6.90, 2.78, 4.00
    Axes: 0, 8, 0, 8
    for .a to 8
        for .b to 8
            if abMz[.a, .b] > 0.28
                Colour: "White"
            else
                Colour: .ink$
            endif
            Text: .b - 0.5, "centre", 8 - .a + 0.62, "half", fixed$(abMz[.a, .b], 3)
            if abObsRow[.a] > 0
                Colour: "{0.50, 0.50, 0.54}"
                Text: .b - 0.5, "centre", 8 - .a + 0.27, "half", fixed$(abObs[.a, .b] / abObsRow[.a], 2)
            endif
        endfor
    endfor
    Font size: 5
    Select inner viewport: 4.70, 6.90, 2.78, 4.00
    Axes: 0, 8, 0, 8
    Colour: .faint$
    for .b to 8
        Text: .b - 0.5, "centre", -0.30, "half", abStateName$[.b]
    endfor
    for .a to 8
        Text: -0.20, "right", 8 - .a + 0.5, "half", abStateName$[.a]
        Text: 8.15, "left", 8 - .a + 0.5, "half", "n=" + string$(abObsRow[.a])
    endfor
    Font size: 4
    Select inner viewport: 4.70, 6.90, 2.78, 4.00
    Axes: 0, 8, 0, 8
    Colour: .faint$
    Text: 4, "centre", -0.85, "half", .l3cap$

    # ---- IV. SEQUENCE OF SCREENS ----
    Select inner viewport: 0.60, 7.70, 4.42, 4.60
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.0, "left", 0.5, "half", "##" + .l4$ + "##"
    Font size: 5
    Colour: .faint$
    Text: 1.0, "right", 0.5, "half", .l4cap$

    Select inner viewport: .left, .right, 4.66, 5.48
    Axes: 0, .duration, 0.5, 8.5
    Paint rectangle: .bg$, 0, .duration, 0.5, 8.5
    for .k to abNScr
        if abScrMode[.k] = 1
            Paint rectangle: .pert$, (.k - 1) * abScreenDur, .k * abScreenDur, 0.5, 8.5
        endif
    endfor
    Select inner viewport: .left, .right, 4.66, 5.48
    Axes: 0, .duration, 0.5, 8.5
    Colour: .ink$
    Line width: 2
    for .k to abNScr
        .y = 9 - abScr[.k]
        Draw line: (.k - 1) * abScreenDur, .y, .k * abScreenDur, .y
        if .k > 1
            Line width: 1
            Colour: .grid$
            Draw line: (.k - 1) * abScreenDur, 9 - abScr[.k - 1], (.k - 1) * abScreenDur, .y
            Colour: .ink$
            Line width: 2
        endif
    endfor
    Line width: 1
    Select inner viewport: .left, .right, 4.66, 5.48
    Axes: 0, .duration, 0.5, 8.5
    Colour: "Black"
    Draw inner box
    Font size: 5
    for .a to 8
        One mark left: 9 - .a, "no", "yes", "no", abStateName$[.a]
    endfor
    Marks bottom every: 1, .tTick, "yes", "yes", "no"

    # ---- V. SPECTROGRAM ----
    Select inner viewport: 0.60, 7.70, 5.74, 5.92
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.0, "left", 0.5, "half", "##" + .l5$ + "##"
    Font size: 5
    Colour: .faint$
    Text: 1.0, "right", 0.5, "half", .l5cap$
    .fTop = 11400
    .specStep = max(0.01, .duration / 1400)
    selectObject: outputID
    .spec = To Spectrogram: 0.02, .fTop, .specStep, 20, "Gaussian"
    Select inner viewport: .left, .right, 5.98, 6.76
    selectObject: .spec
    Paint: 0, 0, 0, .fTop, 100, 1, 50, 6, 0, 0
    removeObject: .spec
    Select inner viewport: .left, .right, 5.98, 6.76
    Axes: 0, .duration, 0, .fTop
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 5
    Marks left every: 1, 2000, "yes", "yes", "no"
    Marks bottom every: 1, .tTick, "yes", "yes", "no"
    Font size: 6
    Text left: "yes", .lFreq$
    Text bottom: "yes", .lTime$

    # ---- SUMMARY ----
    Select inner viewport: 0.60, 7.70, 7.16, 7.70
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Select inner viewport: 0.60, 7.70, 7.16, 7.70
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    .occ$ = ""
    for .a to 8
        .occ$ = .occ$ + abStateName$[.a] + " " + fixed$(abOccEq[.a] / max(1, abNSampled), 2) + "/" + fixed$(abStat[.a], 2) + "  "
    endfor
    Text: 0.02, "left", 0.80, "half", "CHAIN OCCUPANCY / STATIONARY  |  " + .occ$
    Text: 0.02, "left", 0.50, "half",
        ... "SCREENS  |  " + string$(abNScr) + " x 0.5 s  |  " + string$(abNSampled)
        ... + " transitions drawn from the matrix  |  10 streams per screen  |  40 ms sine grains"
    Text: 0.02, "left", 0.20, "half",
        ... "OUTPUT  |  " + string$(abNGrain) + " grains  |  " + fixed$(abNGrain / (abNScr * abScreenDur), 0)
        ... + " per second  |  peak " + fixed$(finalPeak, 3) + "  |  RMS " + fixed$(finalRMS, 4)
    Select inner viewport: 0.60, 7.70, 7.16, 7.70
    Axes: 0, 1, 0, 1
    Colour: "{0.52, 0.52, 0.54}"
    Draw rectangle: 0, 1, 0, 1

    Select inner viewport: 0.60, 7.70, 7.76, 7.92
    Axes: 0, 1, 0, 1
    Font size: 5
    Colour: "{0.42, 0.42, 0.42}"
    Text: 0.0, "left", 0.5, "half", .lNote$

    Colour: "Black"
    Line width: 1
    Font size: 10
    Select outer viewport: 0, 8, 0, 8
endproc
