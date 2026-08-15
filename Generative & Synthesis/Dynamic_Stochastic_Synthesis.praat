# ============================================================
# Praat AudioTools - Dynamic Stochastic Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 reviewed (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# ACCURATE DESCRIPTION
#   Dynamic Stochastic Grain Field:
#   an inhomogeneous-Poisson granular synthesizer with linearly evolving
#   event density and an octave-domain frequency trajectory.
#
#   This is deliberately NOT labelled GENDYN. Xenakis's classic dynamic
#   stochastic synthesis evolves waveform breakpoints through random walks
#   in both breakpoint amplitude and breakpoint time/spacing. This tool is
#   a stochastic granular process and should be described as such.
#
# Event process:
#   Target event intensity
#
#       lambda(t) = d0 + (d1-d0) * t/T
#
#   Grain onset times are generated as a genuine inhomogeneous Poisson
#   process by exponential increments in cumulative-intensity space:
#
#       Lambda(t) = d0*t + (d1-d0)*t^2/(2T)
#
#   followed by exact inversion of Lambda(t).
#
# Frequency process:
#       f_center(t) = f0 * 2^(evolution_octaves * t/T)
#       f_grain     = f_center * 2^(uniform(-jitter,+jitter))
#
# Grain:
#       Hann envelope with random starting phase.
#
# Level:
#   Per-grain amplitude is compensated by expected local overlap
#   sqrt(max(1, lambda(t)*mean_grain_duration)), so changing density changes
#   texture/occupancy without automatically becoming a loudness control.
#
# v0.5 reviewed:
#   - Removed the inaccurate GENDYN claim; this engine is stochastic granular.
#   - Replaced "fixed N + iid density-weighted times" with a genuine
#     inhomogeneous Poisson event process. Total grain count is now stochastic.
#   - Event times are generated chronologically; removed O(N^2) sorting.
#   - Frequency_evolution is explicitly measured in octaves and supports
#     both upward and downward trajectories.
#   - Added Frequency_jitter_octaves and reproducible Random_seed.
#   - Added practical Nyquist protection and low-frequency correction count.
#   - Removed the hidden amplitude fade-to-zero that fought the rising density.
#     Added overlap-energy compensation instead.
#   - Replaced half-sine grains with Hann grains and random grain phase.
#   - Rebuilt synthesis as exact chronological chunks. Grains crossing a chunk
#     boundary retain the same age, phase and envelope on both sides; no grain
#     truncation and no Concatenate-with-overlap timeline distortion.
#   - Spatial modes now operate at grain level with equal-power panning:
#       Stereo Evolution = stochastic left-to-right trajectory
#       Rotating Cloud    = accelerating circular pan trajectory
#       Wide Field        = stochastic near-edge distribution
#     Removed post-mix complementary spectral filtering.
#   - Compact laptop-safe main form + optional grain-details page.
#   - One combined edge fade; one optional final/common normalization.
#   - Visualization rebuilt:
#       A target density vs actual binned Poisson realization
#       B actual rendered grain field
#       C measured spectrogram + sampled grain guides
#       D measured representative-channel waveform
#       compact process/QC summary
# ============================================================

form Dynamic Stochastic Grain Field v0.5
    optionmenu Preset 1
        option Custom (baseline values)
        option Sparse-to-Dense Bloom
        option Steep Density Build
        option Slow Two-Octave Drift
        option Short-Grain Rising Cascade
        option Medium Density Growth
        option Dense Pitch Cloud
        option High-Density Short Grains
        option Sparse Long-Grain Cloud

    positive Duration_s 6.0
    integer Sample_rate_Hz 44100
    positive Base_frequency_Hz 120
    positive Initial_density 30
    positive Final_density 150
    real Frequency_evolution_octaves 1.0

    optionmenu Spatial_mode 1
        option Mono
        option Stereo Evolution
        option Rotating Cloud
        option Wide Field

    boolean Edit_grain_details 0
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---------------------------------------------------------------------------
# DETAILED DEFAULTS (optional compact-form second page)
# ---------------------------------------------------------------------------
min_grain_duration_ms = 20
max_grain_duration_ms = 80
frequency_jitter_octaves = 0.25
random_seed = 0
edge_fade_s = 0.02

# ---------------------------------------------------------------------------
# 0. PRESETS
# ---------------------------------------------------------------------------
preset_name$ = "Custom"

if preset = 2
    base_frequency_Hz = 80
    initial_density = 15
    final_density = 60
    frequency_evolution_octaves = 0.5
    min_grain_duration_ms = 30
    max_grain_duration_ms = 100
    frequency_jitter_octaves = 0.18
    spatial_mode = 1
    preset_name$ = "Sparse-to-Dense Bloom"

elsif preset = 3
    base_frequency_Hz = 100
    initial_density = 20
    final_density = 200
    frequency_evolution_octaves = 1.2
    min_grain_duration_ms = 10
    max_grain_duration_ms = 50
    frequency_jitter_octaves = 0.30
    spatial_mode = 2
    preset_name$ = "Steep Density Build"

elsif preset = 4
    duration_s = 10
    base_frequency_Hz = 60
    initial_density = 10
    final_density = 80
    frequency_evolution_octaves = 2.0
    min_grain_duration_ms = 50
    max_grain_duration_ms = 150
    frequency_jitter_octaves = 0.20
    spatial_mode = 3
    preset_name$ = "Slow Two-Octave Drift"

elsif preset = 5
    base_frequency_Hz = 180
    initial_density = 40
    final_density = 180
    frequency_evolution_octaves = 1.5
    min_grain_duration_ms = 10
    max_grain_duration_ms = 40
    frequency_jitter_octaves = 0.35
    spatial_mode = 4
    preset_name$ = "Short-Grain Rising Cascade"

elsif preset = 6
    duration_s = 8
    base_frequency_Hz = 90
    initial_density = 25
    final_density = 100
    frequency_evolution_octaves = 0.8
    min_grain_duration_ms = 25
    max_grain_duration_ms = 90
    frequency_jitter_octaves = 0.22
    spatial_mode = 2
    preset_name$ = "Medium Density Growth"

elsif preset = 7
    base_frequency_Hz = 110
    initial_density = 35
    final_density = 120
    frequency_evolution_octaves = 1.0
    min_grain_duration_ms = 20
    max_grain_duration_ms = 60
    frequency_jitter_octaves = 0.10
    spatial_mode = 1
    preset_name$ = "Dense Pitch Cloud"

elsif preset = 8
    base_frequency_Hz = 200
    initial_density = 50
    final_density = 250
    frequency_evolution_octaves = 1.8
    min_grain_duration_ms = 8
    max_grain_duration_ms = 30
    frequency_jitter_octaves = 0.40
    spatial_mode = 4
    preset_name$ = "High-Density Short Grains"

elsif preset = 9
    duration_s = 10
    base_frequency_Hz = 70
    initial_density = 8
    final_density = 40
    frequency_evolution_octaves = 0.3
    min_grain_duration_ms = 40
    max_grain_duration_ms = 120
    frequency_jitter_octaves = 0.15
    spatial_mode = 3
    preset_name$ = "Sparse Long-Grain Cloud"
endif

# ---------------------------------------------------------------------------
# OPTIONAL GRAIN-DETAILS PAGE
# ---------------------------------------------------------------------------
if edit_grain_details
    beginPause: "Dynamic Stochastic Grain Field - Grain Details"
        positive: "Min grain duration (ms)", min_grain_duration_ms
        positive: "Max grain duration (ms)", max_grain_duration_ms
        real: "Frequency jitter (octaves)", frequency_jitter_octaves
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
if frequency_evolution_octaves < -8 or frequency_evolution_octaves > 8
    exitScript: "Frequency evolution must be between -8 and +8 octaves."
endif
if frequency_jitter_octaves < 0 or frequency_jitter_octaves > 2
    exitScript: "Frequency jitter must be between 0 and 2 octaves."
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
if random_seed < 0
    exitScript: "Random seed must be 0 or a positive integer."
endif
if edge_fade_s < 0
    exitScript: "Edge fade cannot be negative."
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
minAudible = 20
meanGrainDur = 0.0005*(min_grain_duration_ms + max_grain_duration_ms)
maxGrainDur = max_grain_duration_ms/1000

# Practical Nyquist guard based on the largest possible octave exponent.
maxTrajectoryExponent = max(0, frequency_evolution_octaves) + frequency_jitter_octaves
maxSafeBase = safeTop / (2^maxTrajectoryExponent)
baseWasAdjusted = 0
if base_frequency_Hz > maxSafeBase
    base_frequency_Hz = maxSafeBase
    baseWasAdjusted = 1
endif
if base_frequency_Hz <= 0
    exitScript: "Frequency settings leave no safe carrier range at this sample rate."
endif

# Expected number of events is integral lambda(t) dt.
expectedGrains = 0.5*(initial_density + final_density)*duration_s
if expectedGrains > 8000
    exitScript: "Expected grain count exceeds 8000. Reduce duration or density."
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
# 2. INFO
# ---------------------------------------------------------------------------
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  DYNAMIC STOCHASTIC GRAIN FIELD v0.5"
writeInfoLine: "=============================================="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", fixed$(duration_s,2), " s"
appendInfoLine: "Target density: ", fixed$(initial_density,1), " -> ",
    ... fixed$(final_density,1), " grains/s"
appendInfoLine: "Expected grains: ", fixed$(expectedGrains,1), " (actual count is stochastic)"
appendInfoLine: "Frequency evolution: ", fixed$(frequency_evolution_octaves,2), " octaves"
appendInfoLine: "Frequency jitter: +/-", fixed$(frequency_jitter_octaves,2), " octaves"
appendInfoLine: "Spatial: ", spatial$
appendInfoLine: "Randomness: ", seedLabel$
if baseWasAdjusted
    appendInfoLine: "Base frequency reduced to ", fixed$(base_frequency_Hz,2),
        ... " Hz for Nyquist safety."
endif
appendInfoLine: ""

# ---------------------------------------------------------------------------
# 3. GENUINE INHOMOGENEOUS-POISSON EVENT SCHEDULE
# ---------------------------------------------------------------------------
appendInfoLine: "Generating inhomogeneous-Poisson grain schedule..."

densityDelta = final_density - initial_density
lambdaTotal = expectedGrains
lambdaCum = 0
totalGrains = 0
lowFrequencyCorrections = 0

freqMinRealized = safeTop
freqMaxRealized = minAudible
durSum = 0
ampMinRealized = 1e9
ampMaxRealized = 0
panMinRealized = 1
panMaxRealized = 0
densityMinRealized = min(initial_density, final_density)
densityMaxRealized = max(initial_density, final_density)

scheduleDone = 0
while scheduleDone = 0
    u = max(1e-12, randomUniform(0,1))
    lambdaNext = lambdaCum - ln(u)

    if lambdaNext >= lambdaTotal
        scheduleDone = 1
    elsif totalGrains >= 10000
        exitScript: "Stochastic realization exceeded 10,000 grains. Reduce density or duration."
    else
        lambdaCum = lambdaNext

        if abs(densityDelta) < 1e-12
            t = lambdaCum / initial_density
        else
            disc = initial_density^2 + 2*densityDelta*lambdaCum/duration_s
            if disc < 0
                disc = 0
            endif
            t = duration_s*(-initial_density + sqrt(disc))/densityDelta
        endif

        t = max(0, min(duration_s, t))
        normalizedTime = t/duration_s
        localDensity = initial_density + densityDelta*normalizedTime

        totalGrains = totalGrains + 1
        grain_time[totalGrains] = t

        grain_dur[totalGrains] =
            ... (min_grain_duration_ms
            ... + (max_grain_duration_ms-min_grain_duration_ms)*randomUniform(0,1))/1000
        if grain_time[totalGrains] + grain_dur[totalGrains] > duration_s
            grain_dur[totalGrains] = duration_s - grain_time[totalGrains]
        endif

        centerFreq = base_frequency_Hz * 2^(frequency_evolution_octaves*normalizedTime)
        jitterOct = randomUniform(-frequency_jitter_octaves, frequency_jitter_octaves)
        grain_freq[totalGrains] = centerFreq * 2^jitterOct

        if grain_freq[totalGrains] < minAudible
            grain_freq[totalGrains] = minAudible
            lowFrequencyCorrections = lowFrequencyCorrections + 1
        endif
        if grain_freq[totalGrains] > safeTop
            grain_freq[totalGrains] = safeTop
        endif

        # Expected-overlap compensation: local density changes occupancy rather
        # than silently becoming an amplitude envelope.
        expectedOverlap = max(1, localDensity*meanGrainDur)
        grain_amp[totalGrains] =
            ... 0.55*(0.78 + 0.22*randomUniform(0,1))/sqrt(expectedOverlap)

        grain_phase[totalGrains] = twoPi*randomUniform(0,1)

        # Equal-power grain-level spatial trajectory.
        if spatial_mode = 1
            pan = 0.5

        elsif spatial_mode = 2
            # Left-to-right stochastic evolution.
            pan = normalizedTime + randomUniform(-0.12,0.12)
            pan = max(0.02, min(0.98, pan))

        elsif spatial_mode = 3
            # Accelerating rotation: integrate a linearly rising rotation rate.
            rot0 = 0.08
            rot1 = 0.28
            rotationCycles = rot0*t + 0.5*(rot1-rot0)*t*t/duration_s
            pan = 0.5 + 0.46*sin(twoPi*rotationCycles)

        else
            # Near-edge stochastic field.
            if randomUniform(0,1) < 0.5
                pan = randomUniform(0.03,0.23)
            else
                pan = randomUniform(0.77,0.97)
            endif
        endif
        grain_pan[totalGrains] = pan

        freqMinRealized = min(freqMinRealized, grain_freq[totalGrains])
        freqMaxRealized = max(freqMaxRealized, grain_freq[totalGrains])
        durSum = durSum + grain_dur[totalGrains]
        ampMinRealized = min(ampMinRealized, grain_amp[totalGrains])
        ampMaxRealized = max(ampMaxRealized, grain_amp[totalGrains])
        panMinRealized = min(panMinRealized, pan)
        panMaxRealized = max(panMaxRealized, pan)
    endif
endwhile

if totalGrains < 1
    if seedWasFixed
        random_initializeSafelyAndUnpredictably ()
    endif
    exitScript: "This stochastic realization produced zero grains. Increase density/duration or change the seed."
endif

if seedWasFixed
    random_initializeSafelyAndUnpredictably ()
endif

realizedMeanDensity = totalGrains/duration_s
meanDurRealized = durSum/totalGrains

appendInfoLine: "Actual grains: ", totalGrains
appendInfoLine: "Realized mean density: ", fixed$(realizedMeanDensity,2), " grains/s"

# ---------------------------------------------------------------------------
# 4. REALIZED DENSITY BINS FOR VISUALIZATION / QC
# ---------------------------------------------------------------------------
densityBins = min(32, max(10, round(duration_s*3)))
densityBinWidth = duration_s/densityBins
densityCount# = zero#(densityBins)
densityRealized# = zero#(densityBins)
densityTarget# = zero#(densityBins)

for g to totalGrains
    b = floor(grain_time[g]/densityBinWidth) + 1
    b = max(1, min(densityBins, b))
    densityCount#[b] = densityCount#[b] + 1
endfor

densityRealizedMax = 0
for b to densityBins
    binCenter = (b-0.5)*densityBinWidth
    densityRealized#[b] = densityCount#[b]/densityBinWidth
    densityTarget#[b] = initial_density + densityDelta*(binCenter/duration_s)
    densityRealizedMax = max(densityRealizedMax, densityRealized#[b])
endfor

# ---------------------------------------------------------------------------
# 5. EXACT CHUNKED RENDERING WITH CROSSING-GRAIN CONTINUITY
# ---------------------------------------------------------------------------
appendInfoLine: "Rendering grains..."

chunkDuration = min(1.0, duration_s)
numChunks = ceiling(duration_s/chunkDuration)
candidateStart = 1
maxTermsInChunk = 0

if spatial_mode = 1
    for chunk to numChunks
        chunkStart = (chunk-1)*chunkDuration
        chunkEnd = min(chunk*chunkDuration, duration_s)
        actualChunkDur = chunkEnd-chunkStart

        while candidateStart <= totalGrains and grain_time[candidateStart]+maxGrainDur <= chunkStart
            candidateStart = candidateStart + 1
        endwhile

        formula$ = "0"
        termsInChunk = 0
        g = candidateStart
        while g <= totalGrains and grain_time[g] < chunkEnd
            grainEnd = grain_time[g] + grain_dur[g]
            if grainEnd > chunkStart and grain_dur[g] > 0
                termsInChunk = termsInChunk + 1
                if termsInChunk > 380
                    exitScript: "More than 380 grain terms in a one-second chunk. Reduce density or grain duration."
                endif

                localStart = grain_time[g]-chunkStart
                clipStart = max(0, localStart)
                clipEnd = min(actualChunkDur, localStart+grain_dur[g])

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
                    ... + " then " + sAmp$ + "*" + wave$ + "*" + env$ + " else 0 fi"
                formula$ = formula$ + term$
            endif
            g = g + 1
        endwhile

        maxTermsInChunk = max(maxTermsInChunk, termsInChunk)
        Create Sound from formula: "dsg_m_" + uid$ + "_" + string$(chunk),
            ... 1, 0, actualChunkDur, sample_rate_Hz, formula$
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
        Copy: "dsg_output_" + uid$
        outputSound = selected("Sound")
    endif

    for chunk to numChunks
        removeObject: monoChunk[chunk]
    endfor

else
    candidateStart = 1
    for chunk to numChunks
        chunkStart = (chunk-1)*chunkDuration
        chunkEnd = min(chunk*chunkDuration, duration_s)
        actualChunkDur = chunkEnd-chunkStart

        while candidateStart <= totalGrains and grain_time[candidateStart]+maxGrainDur <= chunkStart
            candidateStart = candidateStart + 1
        endwhile

        leftFormula$ = "0"
        rightFormula$ = "0"
        termsInChunk = 0
        g = candidateStart

        while g <= totalGrains and grain_time[g] < chunkEnd
            grainEnd = grain_time[g]+grain_dur[g]
            if grainEnd > chunkStart and grain_dur[g] > 0
                termsInChunk = termsInChunk + 1
                if termsInChunk > 380
                    exitScript: "More than 380 grain terms in a one-second chunk. Reduce density or grain duration."
                endif

                localStart = grain_time[g]-chunkStart
                clipStart = max(0, localStart)
                clipEnd = min(actualChunkDur, localStart+grain_dur[g])

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
                    ... + " then " + sAmpL$ + "*" + wave$ + "*" + env$ + " else 0 fi"
                rightTerm$ = "+if x>=" + sClipStart$ + " and x<" + sClipEnd$
                    ... + " then " + sAmpR$ + "*" + wave$ + "*" + env$ + " else 0 fi"

                leftFormula$ = leftFormula$ + leftTerm$
                rightFormula$ = rightFormula$ + rightTerm$
            endif
            g = g + 1
        endwhile

        maxTermsInChunk = max(maxTermsInChunk, termsInChunk)

        Create Sound from formula: "dsg_l_" + uid$ + "_" + string$(chunk),
            ... 1, 0, actualChunkDur, sample_rate_Hz, leftFormula$
        leftChunk[chunk] = selected("Sound")

        Create Sound from formula: "dsg_r_" + uid$ + "_" + string$(chunk),
            ... 1, 0, actualChunkDur, sample_rate_Hz, rightFormula$
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
        Copy: "dsg_left_" + uid$
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
        Copy: "dsg_right_" + uid$
        rightSound = selected("Sound")
    endif

    for chunk to numChunks
        removeObject: leftChunk[chunk], rightChunk[chunk]
    endfor

    selectObject: leftSound
    plusObject: rightSound
    Combine to stereo
    outputSound = selected("Sound")
    removeObject: leftSound, rightSound
endif

# ---------------------------------------------------------------------------
# 6. EDGE FADE / FINAL LEVEL
# ---------------------------------------------------------------------------
actualFade = min(edge_fade_s, 0.20*duration_s)
if actualFade > 0
    fadeOutStart = duration_s-actualFade
    selectObject: outputSound
    Formula: "if x<actualFade then self*(x/actualFade) else if x>fadeOutStart then self*((duration_s-x)/actualFade) else self fi fi"
endif

selectObject: outputSound
preNormPeak = Get absolute extremum: 0, 0, "None"
preNormRMS = Get root-mean-square: 0, 0

if normalize_output and preNormPeak > 0
    Scale peak: 0.90
endif

safePreset$ = replace$(preset_name$, " ", "_", 0)
selectObject: outputSound
Rename: "dynamic_stochastic_grains_" + safePreset$

finalPeak = Get absolute extremum: 0, 0, "None"
finalRMS = Get root-mean-square: 0, 0
finalChannels = Get number of channels
finalDuration = Get total duration

# ---------------------------------------------------------------------------
# 7. VISUALIZATION
# ---------------------------------------------------------------------------
if draw_visualization
    @drawVisualization
endif

# ---------------------------------------------------------------------------
# 8. FINAL INFO / PLAY
# ---------------------------------------------------------------------------
selectObject: outputSound
appendInfoLine: ""
appendInfoLine: "Expected/actual grains: ", fixed$(expectedGrains,1), " / ", totalGrains
appendInfoLine: "Frequency range: ", fixed$(freqMinRealized,1), "-",
    ... fixed$(freqMaxRealized,1), " Hz"
appendInfoLine: "Mean grain duration: ", fixed$(meanDurRealized*1000,1), " ms"
appendInfoLine: "Pre-normalization peak/RMS: ", fixed$(preNormPeak,4),
    ... " / ", fixed$(preNormRMS,4)
appendInfoLine: "Final peak/RMS: ", fixed$(finalPeak,4), " / ", fixed$(finalRMS,4)
appendInfoLine: "Maximum terms in any 1-s chunk: ", maxTermsInChunk
appendInfoLine: "Low-frequency corrections: ", lowFrequencyCorrections
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

    Erase all

    # -----------------------------------------------------------------------
    # HEADER
    # -----------------------------------------------------------------------
    Select inner viewport: 0.20, 7.80, 0.05, 0.33
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.55, "half",
        ... "DYNAMIC STOCHASTIC GRAIN FIELD | " + preset_name$

    Select inner viewport: 0.35, 7.65, 0.37, 0.67
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.35,0.35,0.35}"
    Text: 0.5, "centre", 0.68, "half",
        ... "inhomogeneous Poisson events | density "
        ... + fixed$(initial_density,0) + " -> " + fixed$(final_density,0)
        ... + "/s | pitch evolution " + fixed$(frequency_evolution_octaves,2) + " oct"
    Text: 0.5, "centre", 0.20, "half",
        ... "Poisson event time -> evolving pitch + jitter -> Hann grain + random phase -> equal-power spatial field"

    # -----------------------------------------------------------------------
    # PANEL A: TARGET VS ACTUAL DENSITY
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35, 7.65, 0.76, 0.98
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.52, "half",
        ... "A  EVENT DENSITY | target intensity line vs actual binned Poisson realization"

    .densityY = 1.12*max(densityRealizedMax, initial_density, final_density)
    if .densityY <= 0
        .densityY = 1
    endif

    Select inner viewport: .left, .right, 1.05, 2.02
    Axes: 0, duration_s, 0, .densityY
    Paint rectangle: .bg$, 0, duration_s, 0, .densityY

    # Actual realization as lightly filled bins.
    for .b to densityBins
        .x0 = (.b-1)*densityBinWidth
        .x1 = .b*densityBinWidth
        Paint rectangle: "{0.84,0.89,0.96}", .x0, .x1, 0, densityRealized#[.b]
    endfor

    # Target linear intensity.
    Colour: .orange$
    Line width: 1.6
    Draw line: 0, initial_density, duration_s, final_density
    Line width: 1

    # Realized-bin centers.
    Colour: .blue$
    Font size: 4
    for .b to densityBins
        .xc = (.b-0.5)*densityBinWidth
        Text: .xc, "centre", densityRealized#[.b], "half", "."
    endfor

    Colour: "Black"
    Draw inner box
    Marks left: 4, "yes", "yes", "no"
    Marks bottom: 5, "yes", "yes", "no"
    Font size: 6
    Text left: "yes", "Grains/s"

    # -----------------------------------------------------------------------
    # PANEL B: ACTUAL RENDERED GRAIN FIELD
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35, 7.65, 2.18, 2.40
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.52, "half",
        ... "B  ACTUAL GRAIN FIELD | onset-to-end segment at each realized grain frequency"

    .logLo = ln(max(20,0.90*freqMinRealized))
    .logHi = ln(min(safeTop,1.10*freqMaxRealized))
    if .logHi <= .logLo
        .logHi = .logLo+1
    endif

    Select inner viewport: .left, .right, 2.47, 3.51
    Axes: 0, duration_s, .logLo, .logHi
    Paint rectangle: .bg$, 0, duration_s, .logLo, .logHi

    .ticks# = {20,50,100,200,500,1000,2000,5000,10000,20000}
    .nTicks = 10
    Colour: .grid$
    Dotted line
    for .k to .nTicks
        .tf = .ticks#[.k]
        if ln(.tf) >= .logLo and ln(.tf) <= .logHi
            Draw line: 0, ln(.tf), duration_s, ln(.tf)
        endif
    endfor
    Plain line

    .grainStep = max(1, ceiling(totalGrains/1400))
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
            Line width: 0.8
            Draw line: grain_time[.g], ln(grain_freq[.g]),
                ... min(duration_s,grain_time[.g]+grain_dur[.g]), ln(grain_freq[.g])
        endif
    endfor

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
            Text: 0.006*duration_s, "left", ln(.tf), "half", .lab$
        endif
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks bottom: 5, "yes", "yes", "no"
    Font size: 6
    Text left: "yes", "log frequency"

    # -----------------------------------------------------------------------
    # REPRESENTATIVE OUTPUT CHANNEL
    # -----------------------------------------------------------------------
    if finalChannels = 1
        selectObject: outputSound
        Copy: "dsg_display_" + uid$
        .disp = selected("Sound")
    else
        selectObject: outputSound
        Extract one channel: 1
        .leftDisp = selected("Sound")
        .leftRms = Get root-mean-square: 0, 0

        selectObject: outputSound
        Extract one channel: 2
        .rightDisp = selected("Sound")
        .rightRms = Get root-mean-square: 0, 0

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
    Select inner viewport: 0.35, 7.65, 3.67, 3.89
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.52, "half",
        ... "C  MODEL -> MEASUREMENT | measured spectrogram + sampled actual grain guides"

    .specMax = min(safeTop,max(1000,1.30*freqMaxRealized))
    .specStep = max(0.002,duration_s/1100)

    selectObject: .disp
    To Spectrogram: 0.025, .specMax, .specStep, 20, "Gaussian"
    .spec = selected("Spectrogram")

    Select inner viewport: .left, .right, 3.96, 5.04
    selectObject: .spec
    Paint: 0, 0, 0, .specMax, 100, "yes", 50, 6, 0, "no"
    removeObject: .spec

    Axes: 0, duration_s, 0, .specMax
    Colour: .blue$
    Line width: 0.7
    .guideStep = max(1, ceiling(totalGrains/260))
    for .g to totalGrains
        if ((.g-1) mod .guideStep) = 0 and grain_freq[.g] <= .specMax
            Draw line: grain_time[.g], grain_freq[.g],
                ... min(duration_s,grain_time[.g]+grain_dur[.g]), grain_freq[.g]
        endif
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks left: 4, "yes", "yes", "no"
    Marks bottom: 5, "yes", "yes", "no"
    Font size: 6
    Text left: "yes", "Frequency (Hz)"

    # -----------------------------------------------------------------------
    # PANEL D: MEASURED OUTPUT
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35, 7.65, 5.20, 5.42
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.52, "half",
        ... "D  MEASURED OUTPUT | representative channel"

    selectObject: .disp
    .wavePeak = Get absolute extremum: 0, 0, "None"
    if .wavePeak < 0.001
        .wavePeak = 0.001
    endif
    .waveY = 1.05*.wavePeak

    Select inner viewport: .left, .right, 5.49, 6.24
    Axes: 0, duration_s, -.waveY, .waveY
    Paint rectangle: .bg$, 0, duration_s, -.waveY, .waveY
    selectObject: .disp
    Colour: .orange$
    Draw: 0, 0, -.waveY, .waveY, "no", "Curve"

    Colour: "Black"
    Draw inner box
    Marks left: 3, "yes", "yes", "no"
    Marks bottom: 5, "yes", "yes", "no"
    Font size: 6
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"

    removeObject: .disp

    # -----------------------------------------------------------------------
    # MECHANISM / QC
    # -----------------------------------------------------------------------
    Select inner viewport: 0.50, 7.50, 6.48, 7.80
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.93,0.93,0.935}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.25,0.25,0.25}"

    Text: 0.02, "left", 0.81, "half",
        ... "PROCESS  |  lambda(t) linear -> Poisson event times -> pitch trajectory+jitter -> Hann grains"

    Text: 0.02, "left", 0.60, "half",
        ... "EVENTS  |  expected " + fixed$(expectedGrains,1)
        ... + "  |  actual " + string$(totalGrains)
        ... + "  |  realized mean " + fixed$(realizedMeanDensity,2) + "/s"
        ... + "  |  " + seedLabel$

    Text: 0.02, "left", 0.39, "half",
        ... "GRAINS  |  f " + fixed$(freqMinRealized,0) + "-" + fixed$(freqMaxRealized,0) + " Hz"
        ... + "  |  mean duration " + fixed$(meanDurRealized*1000,1) + " ms"
        ... + "  |  " + spatial$

    if normalize_output
        .norm$ = "normalized"
    else
        .norm$ = "raw level"
    endif

    Text: 0.02, "left", 0.18, "half",
        ... "OUTPUT  |  pre-peak " + fixed$(preNormPeak,3)
        ... + "  |  pre-RMS " + fixed$(preNormRMS,4)
        ... + "  |  final peak " + fixed$(finalPeak,3)
        ... + "  |  " + .norm$

    Colour: "{0.52,0.52,0.54}"
    Draw rectangle: 0, 1, 0, 1

    Colour: "Black"
    Line width: 1
    Font size: 10
endproc
