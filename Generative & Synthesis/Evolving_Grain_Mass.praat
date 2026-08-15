# ============================================================
# Praat AudioTools - Evolving Grain Mass.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 reviewed (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   An evolving granular mass driven by a time-varying Poisson event field.
#
#   In ALL evolution modes, Initial_density and Final_density control the
#   actual event intensity:
#
#       lambda(t) = d0 + (d1-d0) * t/T
#
#   Event times are generated as an inhomogeneous Poisson process by
#   exponential increments in cumulative-intensity space:
#
#       Lambda(t) = d0*t + (d1-d0)*t^2/(2T)
#
#   The selected evolution mode then controls the spectral/statistical layer:
#
#   1. Density Only
#      - density evolves
#      - pitch center and pitch spread remain stationary
#
#   2. Density + Pitch Sweep
#      - density evolves
#      - pitch center follows:
#            fc(t) = f0 * 2^(Pitch_evolution_octaves*t/T)
#      - pitch spread remains stationary
#
#   3. Density + Distribution Morph
#      - density evolves
#      - pitch center evolves as above
#      - pitch spread interpolates continuously from Initial_pitch_spread
#        to Final_pitch_spread
#      - expected grain duration moves continuously from long toward short
#
#   Grain frequency is drawn in LOG-frequency space with a clipped Gaussian:
#
#       f = fc * 2^(spread_octaves * z),  z in [-2.5, +2.5]
#
#   Grain amplitude is compensated by expected local overlap, so increasing
#   density changes mass/occupancy rather than acting as an unintended
#   loudness envelope.
#
# v0.4 reviewed:
#   - Initial/Final density now control actual event density in EVERY mode.
#   - Replaced fixed totalGrains + iid times + O(N^2) sorting with a genuine
#     chronological inhomogeneous-Poisson process.
#   - Replaced the abrupt three-stage Statistical Shift with a continuous
#     Distribution Morph in log-frequency spread and grain duration.
#   - Frequency evolution is now explicitly measured in octaves and supports
#     upward or downward trajectories.
#   - Added reproducible Random_seed and practical Nyquist protection.
#   - Added clipped Gaussian pitch distribution in octave space.
#   - Replaced density-as-gain behavior with local overlap-energy compensation.
#   - Added random starting phase and true Hann grain envelopes.
#   - Rebuilt synthesis as chronological local chunks: grains crossing chunk
#     boundaries retain identical age/phase/envelope; no truncation and no
#     Concatenate-with-overlap timeline distortion.
#   - Removed the arbitrary 30-grain batch cap / repeated full-duration Formula.
#   - Spatial modes now work at GRAIN level with equal-power panning.
#     Removed complementary post-mix spectral filters.
#   - Fixed invalid/undefined evolution_type$ reporting.
#   - Fixed stereo object creation pattern: Combine to stereo is followed by
#     selected("Sound") instead of being embedded as an assignment expression.
#   - Compact laptop-safe main form + optional grain-statistics page.
#   - One combined edge fade; one optional final/common normalization.
#   - Visualization rebuilt:
#       A target density vs actual Poisson realization
#       B actual rendered grain field + target pitch center
#       C measured spectrogram + sampled actual grain guides
#       D actual binned pitch mean +/- 1 SD vs target pitch center
#       compact event/statistics/output QC
# ============================================================

form Evolving Grain Mass v0.4
    optionmenu Preset 1
        option Custom (baseline values)
        option Low Cloud Growth
        option Rising Fine Sweep
        option Dense Low Build
        option Slow Wide Sweep
        option Short-Grain Cascade
        option Broadening Bloom
        option High Digital Morph
        option Narrow Rising Band
        option Dense Swarm

    positive Duration_s 5.0
    integer Sample_rate_Hz 44100
    positive Base_frequency_Hz 120
    positive Initial_density 20
    positive Final_density 60
    real Pitch_evolution_octaves 1.0

    optionmenu Evolution_mode 1
        option Density Only
        option Density + Pitch Sweep
        option Density + Distribution Morph

    optionmenu Spatial_mode 1
        option Mono
        option Stereo Evolution
        option Rotating Cloud
        option Wide Field

    boolean Edit_grain_statistics 0
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---------------------------------------------------------------------------
# DETAILED DEFAULTS
# ---------------------------------------------------------------------------
min_grain_ms = 20
max_grain_ms = 80
initial_pitch_spread_octaves = 0.18
final_pitch_spread_octaves = 0.45
random_seed = 0
edge_fade_s = 0.02

# ---------------------------------------------------------------------------
# 0. PRESETS
# ---------------------------------------------------------------------------
preset_name$ = "Custom"

if preset = 2
    duration_s = 6
    initial_density = 10
    final_density = 45
    base_frequency_Hz = 80
    pitch_evolution_octaves = 0
    evolution_mode = 1
    min_grain_ms = 45
    max_grain_ms = 120
    initial_pitch_spread_octaves = 0.22
    final_pitch_spread_octaves = 0.22
    spatial_mode = 1
    preset_name$ = "Low Cloud Growth"

elsif preset = 3
    duration_s = 6
    initial_density = 7
    final_density = 32
    base_frequency_Hz = 140
    pitch_evolution_octaves = 1.1
    evolution_mode = 2
    min_grain_ms = 30
    max_grain_ms = 90
    initial_pitch_spread_octaves = 0.12
    final_pitch_spread_octaves = 0.12
    spatial_mode = 3
    preset_name$ = "Rising Fine Sweep"

elsif preset = 4
    duration_s = 8
    initial_density = 18
    final_density = 110
    base_frequency_Hz = 95
    pitch_evolution_octaves = 0
    evolution_mode = 1
    min_grain_ms = 15
    max_grain_ms = 55
    initial_pitch_spread_octaves = 0.28
    final_pitch_spread_octaves = 0.28
    spatial_mode = 2
    preset_name$ = "Dense Low Build"

elsif preset = 5
    duration_s = 10
    initial_density = 8
    final_density = 35
    base_frequency_Hz = 60
    pitch_evolution_octaves = 1.7
    evolution_mode = 2
    min_grain_ms = 60
    max_grain_ms = 160
    initial_pitch_spread_octaves = 0.20
    final_pitch_spread_octaves = 0.20
    spatial_mode = 3
    preset_name$ = "Slow Wide Sweep"

elsif preset = 6
    duration_s = 5
    initial_density = 28
    final_density = 130
    base_frequency_Hz = 170
    pitch_evolution_octaves = 1.2
    evolution_mode = 2
    min_grain_ms = 8
    max_grain_ms = 35
    initial_pitch_spread_octaves = 0.25
    final_pitch_spread_octaves = 0.25
    spatial_mode = 4
    preset_name$ = "Short-Grain Cascade"

elsif preset = 7
    duration_s = 8
    initial_density = 12
    final_density = 55
    base_frequency_Hz = 105
    pitch_evolution_octaves = 0.55
    evolution_mode = 3
    min_grain_ms = 30
    max_grain_ms = 110
    initial_pitch_spread_octaves = 0.08
    final_pitch_spread_octaves = 0.55
    spatial_mode = 2
    preset_name$ = "Broadening Bloom"

elsif preset = 8
    duration_s = 5
    initial_density = 30
    final_density = 95
    base_frequency_Hz = 200
    pitch_evolution_octaves = 0.8
    evolution_mode = 3
    min_grain_ms = 7
    max_grain_ms = 32
    initial_pitch_spread_octaves = 0.12
    final_pitch_spread_octaves = 0.70
    spatial_mode = 4
    preset_name$ = "High Digital Morph"

elsif preset = 9
    duration_s = 6
    initial_density = 18
    final_density = 55
    base_frequency_Hz = 130
    pitch_evolution_octaves = 1.25
    evolution_mode = 2
    min_grain_ms = 25
    max_grain_ms = 70
    initial_pitch_spread_octaves = 0.08
    final_pitch_spread_octaves = 0.08
    spatial_mode = 1
    preset_name$ = "Narrow Rising Band"

elsif preset = 10
    duration_s = 5
    initial_density = 55
    final_density = 170
    base_frequency_Hz = 150
    pitch_evolution_octaves = 0.35
    evolution_mode = 3
    min_grain_ms = 5
    max_grain_ms = 28
    initial_pitch_spread_octaves = 0.30
    final_pitch_spread_octaves = 0.65
    spatial_mode = 3
    preset_name$ = "Dense Swarm"
endif

# ---------------------------------------------------------------------------
# OPTIONAL COMPACT-FORM DETAIL PAGE
# ---------------------------------------------------------------------------
if edit_grain_statistics
    beginPause: "Evolving Grain Mass - Grain Statistics"
        positive: "Min grain duration (ms)", min_grain_ms
        positive: "Max grain duration (ms)", max_grain_ms
        real: "Initial pitch spread (octaves SD)", initial_pitch_spread_octaves
        real: "Final pitch spread (octaves SD)", final_pitch_spread_octaves
        integer: "Random seed (0 = unpredictable)", random_seed
        real: "Edge fade (s)", edge_fade_s
    endPause: "Run", 1
endif

# ---------------------------------------------------------------------------
# 1. VALIDATION / LABELS
# ---------------------------------------------------------------------------
if duration_s <= 0 or duration_s > 120
    exitScript: "Duration must be > 0 and <= 120 seconds."
endif
if sample_rate_Hz < 8000 or sample_rate_Hz > 192000
    exitScript: "Sample rate must be between 8000 and 192000 Hz."
endif
if base_frequency_Hz <= 0
    exitScript: "Base frequency must be greater than zero."
endif
if initial_density <= 0 or final_density <= 0
    exitScript: "Initial and final density must be greater than zero."
endif
if initial_density > 500 or final_density > 500
    exitScript: "Density is limited to 500 grains/s to keep Praat responsive."
endif
if pitch_evolution_octaves < -8 or pitch_evolution_octaves > 8
    exitScript: "Pitch evolution must be between -8 and +8 octaves."
endif
if min_grain_ms <= 0
    exitScript: "Minimum grain duration must be greater than zero."
endif
if max_grain_ms < min_grain_ms
    exitScript: "Maximum grain duration must be >= minimum grain duration."
endif
if max_grain_ms > 2000
    exitScript: "Maximum grain duration is limited to 2000 ms."
endif
if initial_pitch_spread_octaves < 0 or initial_pitch_spread_octaves > 2
    exitScript: "Initial pitch spread must be between 0 and 2 octaves SD."
endif
if final_pitch_spread_octaves < 0 or final_pitch_spread_octaves > 2
    exitScript: "Final pitch spread must be between 0 and 2 octaves SD."
endif
if random_seed < 0
    exitScript: "Random seed must be 0 or a positive integer."
endif
if edge_fade_s < 0
    exitScript: "Edge fade cannot be negative."
endif

if evolution_mode = 1
    evolution$ = "Density Only"
elsif evolution_mode = 2
    evolution$ = "Density + Pitch Sweep"
else
    evolution$ = "Density + Distribution Morph"
endif

if spatial_mode = 1
    spatial$ = "Mono"
elsif spatial_mode = 2
    spatial$ = "Stereo Evolution"
elsif spatial_mode = 3
    spatial$ = "Rotating Cloud"
else
    spatial$ = "Wide Field"
endif

twoPi = 2*pi
safeTop = 0.45*sample_rate_Hz
minFrequency = 20
maxGrainDur = max_grain_ms/1000
minGrainDur = min_grain_ms/1000

# ---------------------------------------------------------------------------
# 2. PRACTICAL FREQUENCY HEADROOM
# ---------------------------------------------------------------------------
if evolution_mode = 1
    maxCenterExponent = 0
    maxSpread = initial_pitch_spread_octaves
elsif evolution_mode = 2
    maxCenterExponent = max(0,pitch_evolution_octaves)
    maxSpread = initial_pitch_spread_octaves
else
    maxCenterExponent = max(0,pitch_evolution_octaves)
    maxSpread = max(initial_pitch_spread_octaves,final_pitch_spread_octaves)
endif

# Gaussian pitch draw is clipped at +/-2.5 SD.
maxPossibleExponent = maxCenterExponent + 2.5*maxSpread
maxSafeBase = safeTop/(2^maxPossibleExponent)
baseWasAdjusted = 0
if base_frequency_Hz > maxSafeBase
    base_frequency_Hz = maxSafeBase
    baseWasAdjusted = 1
endif
if base_frequency_Hz <= 0
    exitScript: "Frequency settings leave no practical Nyquist headroom."
endif

expectedGrains = 0.5*(initial_density+final_density)*duration_s
if expectedGrains > 7000
    exitScript: "Expected grain count exceeds 7000. Reduce duration or density."
endif

uid$ = string$(randomInteger(10000,99999))

seedWasFixed = 0
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedWasFixed = 1
    seedLabel$ = "seed " + string$(random_seed)
else
    seedLabel$ = "seed random"
endif

# ---------------------------------------------------------------------------
# 3. INFO
# ---------------------------------------------------------------------------
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  EVOLVING GRAIN MASS v0.4"
writeInfoLine: "=============================================="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Mode: ", evolution$
appendInfoLine: "Duration: ", fixed$(duration_s,2), " s"
appendInfoLine: "Target density: ", fixed$(initial_density,1), " -> ",
    ... fixed$(final_density,1), " grains/s"
appendInfoLine: "Expected grains: ", fixed$(expectedGrains,1), " (actual count is stochastic)"
appendInfoLine: "Pitch evolution: ", fixed$(pitch_evolution_octaves,2), " octaves"
appendInfoLine: "Pitch spread: ", fixed$(initial_pitch_spread_octaves,2), " -> ",
    ... fixed$(final_pitch_spread_octaves,2), " octaves SD"
appendInfoLine: "Spatial: ", spatial$
appendInfoLine: "Randomness: ", seedLabel$
if baseWasAdjusted
    appendInfoLine: "Base frequency reduced to ", fixed$(base_frequency_Hz,2),
        ... " Hz for sampling headroom."
endif
appendInfoLine: ""

# ---------------------------------------------------------------------------
# 4. INHOMOGENEOUS-POISSON EVENT SCHEDULE
# ---------------------------------------------------------------------------
densityDelta = final_density-initial_density
lambdaTotal = expectedGrains
lambdaCum = 0
totalGrains = 0
scheduleDone = 0

freqMinRealized = safeTop
freqMaxRealized = minFrequency
durSum = 0
lowFrequencyCorrections = 0
nyquistCorrections = 0
ampMinRealized = 1e9
ampMaxRealized = 0
panMinRealized = 1
panMaxRealized = 0

while scheduleDone = 0
    u = max(1e-12,randomUniform(0,1))
    lambdaNext = lambdaCum-ln(u)

    if lambdaNext >= lambdaTotal
        scheduleDone = 1

    elsif totalGrains >= 9000
        exitScript: "Stochastic realization exceeded 9000 grains. Reduce density or duration."

    else
        lambdaCum = lambdaNext

        if abs(densityDelta) < 1e-12
            t = lambdaCum/initial_density
        else
            discriminant = initial_density^2 + 2*densityDelta*lambdaCum/duration_s
            discriminant = max(0,discriminant)
            t = duration_s*(-initial_density+sqrt(discriminant))/densityDelta
        endif

        t = max(0,min(duration_s,t))
        tau = t/duration_s
        localDensity = initial_density+densityDelta*tau

        totalGrains = totalGrains+1
        grain_time[totalGrains] = t

        # ---- Evolving spectral/statistical layer --------------------------
        if evolution_mode = 1
            centerFreq = base_frequency_Hz
            spreadOct = initial_pitch_spread_octaves
            expectedDur = 0.5*(minGrainDur+maxGrainDur)
            grainDur = minGrainDur+(maxGrainDur-minGrainDur)*randomUniform(0,1)

        elsif evolution_mode = 2
            centerFreq = base_frequency_Hz*2^(pitch_evolution_octaves*tau)
            spreadOct = initial_pitch_spread_octaves
            expectedDur = 0.5*(minGrainDur+maxGrainDur)
            grainDur = minGrainDur+(maxGrainDur-minGrainDur)*randomUniform(0,1)

        else
            centerFreq = base_frequency_Hz*2^(pitch_evolution_octaves*tau)
            spreadOct = initial_pitch_spread_octaves +
                ... (final_pitch_spread_octaves-initial_pitch_spread_octaves)*tau

            # Continuous long -> short duration morphology.
            durationCenter = maxGrainDur+(minGrainDur-maxGrainDur)*tau
            durationHalfRange = 0.25*(maxGrainDur-minGrainDur)
            grainDur = durationCenter +
                ... randomUniform(-durationHalfRange,durationHalfRange)
            grainDur = max(minGrainDur,min(maxGrainDur,grainDur))
            expectedDur = durationCenter
        endif

        grain_center[totalGrains] = centerFreq
        grain_spread[totalGrains] = spreadOct

        z = randomGauss(0,1)
        z = max(-2.5,min(2.5,z))
        grainFreq = centerFreq*2^(spreadOct*z)

        if grainFreq < minFrequency
            grainFreq = minFrequency
            lowFrequencyCorrections = lowFrequencyCorrections+1
        endif
        if grainFreq > safeTop
            grainFreq = safeTop
            nyquistCorrections = nyquistCorrections+1
        endif

        grain_freq[totalGrains] = grainFreq

        if t+grainDur > duration_s
            grainDur = duration_s-t
        endif
        grain_dur[totalGrains] = grainDur

        # Density/overlap compensation.
        expectedOverlap = max(1,localDensity*max(1/sample_rate_Hz,expectedDur))
        grainAmp = 0.58*(0.82+0.18*randomUniform(0,1))/sqrt(expectedOverlap)
        grain_amp[totalGrains] = grainAmp

        grain_phase[totalGrains] = twoPi*randomUniform(0,1)

        # ---- Grain-level equal-power spatial model ------------------------
        if spatial_mode = 1
            pan = 0.5

        elsif spatial_mode = 2
            # Global L->R evolution with local stochastic deviation.
            pan = tau+randomUniform(-0.10,0.10)
            pan = max(0.02,min(0.98,pan))

        elsif spatial_mode = 3
            # Accelerating angular trajectory.
            rotStart = 0.06
            rotEnd = 0.24
            rotationCycles = rotStart*t +
                ... 0.5*(rotEnd-rotStart)*t*t/duration_s
            pan = 0.5+0.46*sin(twoPi*rotationCycles)

        else
            # Stochastic near-edge positions.
            if randomUniform(0,1) < 0.5
                pan = randomUniform(0.03,0.25)
            else
                pan = randomUniform(0.75,0.97)
            endif
        endif

        grain_pan[totalGrains] = pan

        freqMinRealized = min(freqMinRealized,grainFreq)
        freqMaxRealized = max(freqMaxRealized,grainFreq)
        durSum = durSum+grainDur
        ampMinRealized = min(ampMinRealized,grainAmp)
        ampMaxRealized = max(ampMaxRealized,grainAmp)
        panMinRealized = min(panMinRealized,pan)
        panMaxRealized = max(panMaxRealized,pan)
    endif
endwhile

if totalGrains < 1
    if seedWasFixed
        random_initializeSafelyAndUnpredictably ()
    endif
    exitScript: "This stochastic realization produced zero grains."
endif

if seedWasFixed
    random_initializeSafelyAndUnpredictably ()
endif

realizedMeanDensity = totalGrains/duration_s
meanDurRealized = durSum/totalGrains

# ---------------------------------------------------------------------------
# 5. BIN ACTUAL REALIZATION FOR VISUALIZATION / QC
# ---------------------------------------------------------------------------
statBins = min(32,max(10,round(duration_s*3)))
statBinWidth = duration_s/statBins

count# = zero#(statBins)
freqLogSum# = zero#(statBins)
freqLogSqSum# = zero#(statBins)
durBinSum# = zero#(statBins)

for g to totalGrains
    b = floor(grain_time[g]/statBinWidth)+1
    b = max(1,min(statBins,b))

    lf = ln(grain_freq[g])
    count#[b] = count#[b]+1
    freqLogSum#[b] = freqLogSum#[b]+lf
    freqLogSqSum#[b] = freqLogSqSum#[b]+lf*lf
    durBinSum#[b] = durBinSum#[b]+grain_dur[g]
endfor

densityRealized# = zero#(statBins)
densityTarget# = zero#(statBins)
meanLogFreq# = zero#(statBins)
sdLogFreq# = zero#(statBins)
meanDurBin# = zero#(statBins)
centerTarget# = zero#(statBins)

densityRealizedMax = 0
firstNonemptyBin = 0
lastNonemptyBin = 0

for b to statBins
    binCenter = (b-0.5)*statBinWidth
    tau = binCenter/duration_s

    densityRealized#[b] = count#[b]/statBinWidth
    densityTarget#[b] = initial_density+densityDelta*tau
    densityRealizedMax = max(densityRealizedMax,densityRealized#[b])

    if evolution_mode = 1
        centerTarget#[b] = base_frequency_Hz
    else
        centerTarget#[b] = base_frequency_Hz*2^(pitch_evolution_octaves*tau)
    endif

    if count#[b] > 0
        meanLogFreq#[b] = freqLogSum#[b]/count#[b]
        varianceLog = freqLogSqSum#[b]/count#[b]-meanLogFreq#[b]^2
        sdLogFreq#[b] = sqrt(max(0,varianceLog))
        meanDurBin#[b] = durBinSum#[b]/count#[b]

        if firstNonemptyBin = 0
            firstNonemptyBin = b
        endif
        lastNonemptyBin = b
    endif
endfor

if firstNonemptyBin > 0
    earlyMeanDur = meanDurBin#[firstNonemptyBin]
    lateMeanDur = meanDurBin#[lastNonemptyBin]
else
    earlyMeanDur = 0
    lateMeanDur = 0
endif

# ---------------------------------------------------------------------------
# 6. EXACT CHUNKED RENDERING
# ---------------------------------------------------------------------------
appendInfoLine: "Rendering actual grain mass..."

chunkDuration = min(1.0,duration_s)
numChunks = ceiling(duration_s/chunkDuration)
candidateStart = 1
maxTermsInChunk = 0

if spatial_mode = 1

    for chunk to numChunks
        chunkStart = (chunk-1)*chunkDuration
        chunkEnd = min(chunk*chunkDuration,duration_s)
        actualChunkDur = chunkEnd-chunkStart

        while candidateStart <= totalGrains and
            ... grain_time[candidateStart]+maxGrainDur <= chunkStart
            candidateStart = candidateStart+1
        endwhile

        formula$ = "0"
        termsInChunk = 0
        g = candidateStart

        while g <= totalGrains and grain_time[g] < chunkEnd
            grainEnd = grain_time[g]+grain_dur[g]

            if grainEnd > chunkStart and grain_dur[g] > 0
                termsInChunk = termsInChunk+1
                if termsInChunk > 400
                    exitScript: "More than 400 grain terms in a 1-second chunk. Reduce density or grain duration."
                endif

                localStart = grain_time[g]-chunkStart
                clipStart = max(0,localStart)
                clipEnd = min(actualChunkDur,localStart+grain_dur[g])

                sLocal$ = fixed$(localStart,9)
                sClipStart$ = fixed$(clipStart,9)
                sClipEnd$ = fixed$(clipEnd,9)
                sDur$ = fixed$(grain_dur[g],9)
                sFreq$ = fixed$(grain_freq[g],6)
                sAmp$ = fixed$(grain_amp[g],8)
                sPhase$ = fixed$(grain_phase[g],8)

                age$ = "(x-(" + sLocal$ + "))"
                env$ = "0.5*(1-cos(2*pi*" + age$ + "/" + sDur$ + "))"
                wave$ = "sin(2*pi*" + sFreq$ + "*" + age$ + "+" + sPhase$ + ")"

                term$ = "+if x>=" + sClipStart$ + " and x<" + sClipEnd$
                    ... + " then " + sAmp$ + "*" + wave$ + "*" + env$
                    ... + " else 0 fi"

                formula$ = formula$+term$
            endif
            g = g+1
        endwhile

        maxTermsInChunk = max(maxTermsInChunk,termsInChunk)

        Create Sound from formula: "egm_m_" + uid$ + "_" + string$(chunk),
            ... 1,0,actualChunkDur,sample_rate_Hz,formula$
        monoChunk[chunk] = selected("Sound")
    endfor

    selectObject: monoChunk[1]
    if numChunks > 1
        for chunk from 2 to numChunks
            plusObject: monoChunk[chunk]
        endfor
        Concatenate
        outputSound = selected("Sound")
    else
        Copy: "egm_output_" + uid$
        outputSound = selected("Sound")
    endif

    for chunk to numChunks
        removeObject: monoChunk[chunk]
    endfor

else
    candidateStart = 1

    for chunk to numChunks
        chunkStart = (chunk-1)*chunkDuration
        chunkEnd = min(chunk*chunkDuration,duration_s)
        actualChunkDur = chunkEnd-chunkStart

        while candidateStart <= totalGrains and
            ... grain_time[candidateStart]+maxGrainDur <= chunkStart
            candidateStart = candidateStart+1
        endwhile

        leftFormula$ = "0"
        rightFormula$ = "0"
        termsInChunk = 0
        g = candidateStart

        while g <= totalGrains and grain_time[g] < chunkEnd
            grainEnd = grain_time[g]+grain_dur[g]

            if grainEnd > chunkStart and grain_dur[g] > 0
                termsInChunk = termsInChunk+1
                if termsInChunk > 400
                    exitScript: "More than 400 grain terms in a 1-second chunk. Reduce density or grain duration."
                endif

                localStart = grain_time[g]-chunkStart
                clipStart = max(0,localStart)
                clipEnd = min(actualChunkDur,localStart+grain_dur[g])

                leftGain = cos(0.5*pi*grain_pan[g])
                rightGain = sin(0.5*pi*grain_pan[g])

                sLocal$ = fixed$(localStart,9)
                sClipStart$ = fixed$(clipStart,9)
                sClipEnd$ = fixed$(clipEnd,9)
                sDur$ = fixed$(grain_dur[g],9)
                sFreq$ = fixed$(grain_freq[g],6)
                sAmpL$ = fixed$(grain_amp[g]*leftGain,8)
                sAmpR$ = fixed$(grain_amp[g]*rightGain,8)
                sPhase$ = fixed$(grain_phase[g],8)

                age$ = "(x-(" + sLocal$ + "))"
                env$ = "0.5*(1-cos(2*pi*" + age$ + "/" + sDur$ + "))"
                wave$ = "sin(2*pi*" + sFreq$ + "*" + age$ + "+" + sPhase$ + ")"

                leftTerm$ = "+if x>=" + sClipStart$ + " and x<" + sClipEnd$
                    ... + " then " + sAmpL$ + "*" + wave$ + "*" + env$
                    ... + " else 0 fi"
                rightTerm$ = "+if x>=" + sClipStart$ + " and x<" + sClipEnd$
                    ... + " then " + sAmpR$ + "*" + wave$ + "*" + env$
                    ... + " else 0 fi"

                leftFormula$ = leftFormula$+leftTerm$
                rightFormula$ = rightFormula$+rightTerm$
            endif
            g = g+1
        endwhile

        maxTermsInChunk = max(maxTermsInChunk,termsInChunk)

        Create Sound from formula: "egm_l_" + uid$ + "_" + string$(chunk),
            ... 1,0,actualChunkDur,sample_rate_Hz,leftFormula$
        leftChunk[chunk] = selected("Sound")

        Create Sound from formula: "egm_r_" + uid$ + "_" + string$(chunk),
            ... 1,0,actualChunkDur,sample_rate_Hz,rightFormula$
        rightChunk[chunk] = selected("Sound")
    endfor

    selectObject: leftChunk[1]
    if numChunks > 1
        for chunk from 2 to numChunks
            plusObject: leftChunk[chunk]
        endfor
        Concatenate
        leftSound = selected("Sound")
    else
        Copy: "egm_left_" + uid$
        leftSound = selected("Sound")
    endif

    selectObject: rightChunk[1]
    if numChunks > 1
        for chunk from 2 to numChunks
            plusObject: rightChunk[chunk]
        endfor
        Concatenate
        rightSound = selected("Sound")
    else
        Copy: "egm_right_" + uid$
        rightSound = selected("Sound")
    endif

    for chunk to numChunks
        removeObject: leftChunk[chunk],rightChunk[chunk]
    endfor

    selectObject: leftSound
    plusObject: rightSound
    Combine to stereo
    outputSound = selected("Sound")

    removeObject: leftSound,rightSound
endif

# ---------------------------------------------------------------------------
# 7. EDGE FADE / FINAL LEVEL
# ---------------------------------------------------------------------------
actualFade = min(edge_fade_s,0.20*duration_s)
if actualFade > 0
    fadeOutStart = duration_s-actualFade
    selectObject: outputSound
    Formula: "if x<actualFade then self*(x/actualFade) else if x>fadeOutStart then self*((duration_s-x)/actualFade) else self fi fi"
endif

selectObject: outputSound
preNormPeak = Get absolute extremum: 0,0,"None"
preNormRMS = Get root-mean-square: 0,0

if normalize_output and preNormPeak > 0
    Scale peak: 0.90
endif

safePreset$ = replace$(preset_name$," ","_",0)
selectObject: outputSound
Rename: "evolving_grain_mass_" + safePreset$

finalPeak = Get absolute extremum: 0,0,"None"
finalRMS = Get root-mean-square: 0,0
finalChannels = Get number of channels
finalDuration = Get total duration

# ---------------------------------------------------------------------------
# 8. VISUALIZATION
# ---------------------------------------------------------------------------
if draw_visualization
    @drawVisualization
endif

# ---------------------------------------------------------------------------
# 9. FINAL INFO / PLAY
# ---------------------------------------------------------------------------
selectObject: outputSound
appendInfoLine: ""
appendInfoLine: "Expected/actual grains: ", fixed$(expectedGrains,1), " / ", totalGrains
appendInfoLine: "Realized mean density: ", fixed$(realizedMeanDensity,2), " grains/s"
appendInfoLine: "Frequency range: ", fixed$(freqMinRealized,1), "-",
    ... fixed$(freqMaxRealized,1), " Hz"
appendInfoLine: "Mean grain duration: ", fixed$(meanDurRealized*1000,1), " ms"
if evolution_mode = 3
    appendInfoLine: "Early/late binned mean duration: ",
        ... fixed$(earlyMeanDur*1000,1), " / ", fixed$(lateMeanDur*1000,1), " ms"
endif
appendInfoLine: "Pre-normalization peak/RMS: ", fixed$(preNormPeak,4),
    ... " / ", fixed$(preNormRMS,4)
appendInfoLine: "Final peak/RMS: ", fixed$(finalPeak,4),
    ... " / ", fixed$(finalRMS,4)
appendInfoLine: "Maximum terms in any 1-s chunk: ", maxTermsInChunk
appendInfoLine: "Low/high frequency corrections: ",
    ... lowFrequencyCorrections, " / ", nyquistCorrections
appendInfoLine: "Done: ", selected$("Sound")

if play_result
    Play
endif

selectObject: outputSound


# ===========================================================================
# PROCEDURE: RESEARCH-GRADE VISUALIZATION
# ===========================================================================
procedure drawVisualization

    .left = 0.78
    .right = 7.58
    .bg$ = "{0.975,0.975,0.978}"
    .grid$ = "{0.80,0.80,0.82}"
    .blue$ = "{0.18,0.43,0.72}"
    .orange$ = "{0.76,0.38,0.18}"
    .green$ = "{0.25,0.58,0.38}"
    .purple$ = "{0.52,0.30,0.62}"

    Erase all

    # -----------------------------------------------------------------------
    # HEADER
    # -----------------------------------------------------------------------
    Select inner viewport: 0.20,7.80,0.05,0.33
    Axes: 0,1,0,1
    Font size: 12
    Colour: "Black"
    Text: 0.5,"centre",0.55,"half",
        ... "EVOLVING GRAIN MASS | " + preset_name$

    Select inner viewport: 0.35,7.65,0.37,0.67
    Axes: 0,1,0,1
    Font size: 6
    Colour: "{0.35,0.35,0.35}"
    Text: 0.5,"centre",0.68,"half",
        ... evolution$ + " | density " + fixed$(initial_density,0)
        ... + " -> " + fixed$(final_density,0) + "/s | pitch "
        ... + fixed$(pitch_evolution_octaves,2) + " oct | " + spatial$
    Text: 0.5,"centre",0.20,"half",
        ... "Poisson event field -> evolving log-frequency statistics -> Hann grains -> equal-power spatial mass"

    # -----------------------------------------------------------------------
    # PANEL A: DENSITY TARGET VS REALIZATION
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,0.76,0.98
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "A  EVENT DENSITY | target intensity vs actual binned Poisson realization"

    .densityY = 1.12*max(densityRealizedMax,initial_density,final_density)
    if .densityY <= 0
        .densityY = 1
    endif

    Select inner viewport: .left,.right,1.05,1.98
    Axes: 0,duration_s,0,.densityY
    Paint rectangle: .bg$,0,duration_s,0,.densityY

    for .b to statBins
        .x0 = (.b-1)*statBinWidth
        .x1 = .b*statBinWidth
        Paint rectangle: "{0.84,0.89,0.96}",.x0,.x1,0,densityRealized#[.b]
    endfor

    Colour: .orange$
    Line width: 1.6
    Draw line: 0,initial_density,duration_s,final_density
    Line width: 1

    Colour: .blue$
    Font size: 4
    for .b to statBins
        .xc = (.b-0.5)*statBinWidth
        Text: .xc,"centre",densityRealized#[.b],"half","."
    endfor

    Colour: "Black"
    Draw inner box
    Marks left: 4,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","Grains/s"

    # -----------------------------------------------------------------------
    # PANEL B: ACTUAL GRAIN FIELD
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,2.14,2.36
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "B  ACTUAL GRAIN FIELD | horizontal extent = duration; curve = target pitch center"

    .logLo = ln(max(20,0.88*freqMinRealized))
    .logHi = ln(min(safeTop,1.12*freqMaxRealized))
    if .logHi <= .logLo
        .logHi = .logLo+1
    endif

    Select inner viewport: .left,.right,2.43,3.47
    Axes: 0,duration_s,.logLo,.logHi
    Paint rectangle: .bg$,0,duration_s,.logLo,.logHi

    .ticks# = {20,50,100,200,500,1000,2000,5000,10000,20000}
    .nTicks = 10

    Colour: .grid$
    Dotted line
    for .k to .nTicks
        .tf = .ticks#[.k]
        if ln(.tf) >= .logLo and ln(.tf) <= .logHi
            Draw line: 0,ln(.tf),duration_s,ln(.tf)
        endif
    endfor
    Plain line

    .grainStep = max(1,ceiling(totalGrains/1500))
    for .g to totalGrains
        if ((.g-1) mod .grainStep) = 0
            .pan = grain_pan[.g]

            if spatial_mode = 1
                Colour: .blue$
            elsif .pan < 0.35
                Colour: .blue$
            elsif .pan > 0.65
                Colour: .orange$
            else
                Colour: .green$
            endif

            Draw line: grain_time[.g],ln(grain_freq[.g]),
                ... min(duration_s,grain_time[.g]+grain_dur[.g]),ln(grain_freq[.g])
        endif
    endfor

    # Target pitch-center trajectory.
    Colour: .purple$
    Line width: 1.6
    for .b from 2 to statBins
        .x1 = (.b-1.5)*statBinWidth
        .x2 = (.b-0.5)*statBinWidth
        Draw line: .x1,ln(centerTarget#[.b-1]),.x2,ln(centerTarget#[.b])
    endfor
    Line width: 1

    Colour: "{0.42,0.42,0.45}"
    Font size: 4
    for .k to .nTicks
        .tf = .ticks#[.k]
        if ln(.tf) >= .logLo and ln(.tf) <= .logHi
            if .tf >= 1000
                .lab$ = fixed$(.tf/1000,0)+"k"
            else
                .lab$ = fixed$(.tf,0)
            endif
            Text: 0.006*duration_s,"left",ln(.tf),"half",.lab$
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","log frequency"

    # -----------------------------------------------------------------------
    # REPRESENTATIVE OUTPUT CHANNEL
    # -----------------------------------------------------------------------
    if finalChannels = 1
        selectObject: outputSound
        Copy: "egm_display_" + uid$
        .disp = selected("Sound")
    else
        selectObject: outputSound
        Extract one channel: 1
        .leftDisp = selected("Sound")
        .leftRms = Get root-mean-square: 0,0

        selectObject: outputSound
        Extract one channel: 2
        .rightDisp = selected("Sound")
        .rightRms = Get root-mean-square: 0,0

        if .rightRms > .leftRms
            removeObject: .leftDisp
            .disp = .rightDisp
        else
            removeObject: .rightDisp
            .disp = .leftDisp
        endif
    endif

    # -----------------------------------------------------------------------
    # PANEL C: MODEL -> MEASUREMENT
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,3.63,3.85
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "C  MODEL -> MEASUREMENT | measured spectrogram + sampled actual grains"

    .specMax = min(safeTop,max(1000,1.30*freqMaxRealized))
    .specStep = max(0.002,duration_s/1100)

    selectObject: .disp
    To Spectrogram: 0.025,.specMax,.specStep,20,"Gaussian"
    .spec = selected("Spectrogram")

    Select inner viewport: .left,.right,3.92,4.96
    selectObject: .spec
    Paint: 0,0,0,.specMax,100,"yes",50,6,0,"no"
    removeObject: .spec

    Axes: 0,duration_s,0,.specMax
    Colour: .blue$
    Line width: 0.7
    .guideStep = max(1,ceiling(totalGrains/260))
    for .g to totalGrains
        if ((.g-1) mod .guideStep) = 0 and grain_freq[.g] <= .specMax
            Draw line: grain_time[.g],grain_freq[.g],
                ... min(duration_s,grain_time[.g]+grain_dur[.g]),grain_freq[.g]
        endif
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks left: 4,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","Frequency (Hz)"

    # -----------------------------------------------------------------------
    # PANEL D: ACTUAL BINNED PITCH STATISTICS
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,5.12,5.34
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "D  ACTUAL PITCH STATISTICS | geometric mean +/- 1 log-SD vs target center"

    Select inner viewport: .left,.right,5.41,6.31
    Axes: 0,duration_s,.logLo,.logHi
    Paint rectangle: .bg$,0,duration_s,.logLo,.logHi

    Colour: .grid$
    Dotted line
    for .k to .nTicks
        .tf = .ticks#[.k]
        if ln(.tf) >= .logLo and ln(.tf) <= .logHi
            Draw line: 0,ln(.tf),duration_s,ln(.tf)
        endif
    endfor
    Plain line

    # +/- 1 SD vertical bars and actual mean line.
    Colour: "{0.60,0.70,0.84}"
    for .b to statBins
        if count#[.b] > 1
            .xc = (.b-0.5)*statBinWidth
            Draw line: .xc,meanLogFreq#[.b]-sdLogFreq#[.b],
                ... .xc,meanLogFreq#[.b]+sdLogFreq#[.b]
        endif
    endfor

    Colour: .blue$
    Line width: 1.5
    for .b from 2 to statBins
        if count#[.b-1] > 0 and count#[.b] > 0
            .x1 = (.b-1.5)*statBinWidth
            .x2 = (.b-0.5)*statBinWidth
            Draw line: .x1,meanLogFreq#[.b-1],.x2,meanLogFreq#[.b]
        endif
    endfor

    Colour: .purple$
    Line width: 1.2
    for .b from 2 to statBins
        .x1 = (.b-1.5)*statBinWidth
        .x2 = (.b-0.5)*statBinWidth
        Draw line: .x1,ln(centerTarget#[.b-1]),.x2,ln(centerTarget#[.b])
    endfor
    Line width: 1

    Colour: "{0.42,0.42,0.45}"
    Font size: 4
    for .k to .nTicks
        .tf = .ticks#[.k]
        if ln(.tf) >= .logLo and ln(.tf) <= .logHi
            if .tf >= 1000
                .lab$ = fixed$(.tf/1000,0)+"k"
            else
                .lab$ = fixed$(.tf,0)
            endif
            Text: 0.006*duration_s,"left",ln(.tf),"half",.lab$
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","log frequency"
    Text bottom: "yes","Time (s)"

    removeObject: .disp

    # -----------------------------------------------------------------------
    # MECHANISM / QC
    # -----------------------------------------------------------------------
    Select inner viewport: 0.50,7.50,6.55,7.82
    Axes: 0,1,0,1
    Paint rectangle: "{0.93,0.93,0.935}",0,1,0,1

    Font size: 6
    Colour: "{0.25,0.25,0.25}"

    Text: 0.02,"left",0.80,"half",
        ... "PROCESS  |  lambda(t) -> Poisson times -> evolving log-frequency distribution -> Hann grains"

    Text: 0.02,"left",0.58,"half",
        ... "EVENTS  |  expected " + fixed$(expectedGrains,1)
        ... + "  |  actual " + string$(totalGrains)
        ... + "  |  mean " + fixed$(realizedMeanDensity,2) + "/s"
        ... + "  |  " + seedLabel$

    Text: 0.02,"left",0.37,"half",
        ... "GRAINS  |  f " + fixed$(freqMinRealized,0) + "-"
        ... + fixed$(freqMaxRealized,0) + " Hz"
        ... + "  |  mean dur " + fixed$(meanDurRealized*1000,1) + " ms"
        ... + "  |  " + spatial$

    if normalize_output
        .norm$ = "normalized"
    else
        .norm$ = "raw level"
    endif

    Text: 0.02,"left",0.16,"half",
        ... "OUTPUT  |  pre-peak " + fixed$(preNormPeak,3)
        ... + "  |  pre-RMS " + fixed$(preNormRMS,4)
        ... + "  |  final peak " + fixed$(finalPeak,3)
        ... + "  |  " + .norm$

    Colour: "{0.52,0.52,0.54}"
    Draw rectangle: 0,1,0,1

    Colour: "Black"
    Line width: 1
    Font size: 10
endproc
