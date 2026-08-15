# ============================================================
# Praat AudioTools - Poisson_Point_Process_Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.6 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Stochastic grain synthesis using Poisson point processes.
#   Events occur at random times with exponentially distributed
#   inter-arrival intervals - a mathematically rigorous approach
#   to statistical texture synthesis (cf. Xenakis).
#
#   Each event triggers a short windowed grain with randomized
#   frequency and duration. Independent L/R processes create
#   spatial depth.
#
# Usage:
#   Run this script and select a preset or customize parameters.
#
# Changelog v0.3:
#   - Chunked synthesis (prevents formula explosion), added viz
#
# Changelog v0.4:
#   - Fixed asymmetric in-place stereo crossfeed and rebuilt visualization.
#
# Changelog v0.5:
#   - Replaced crossfeed stereo control with exact mid/side width mapping.
#   - Added Nyquist guards, optional deterministic seed, and zero-event safety.
#
# Changelog v0.6:
#   - Reorganized the form into a compact musical page plus optional Details.
#   - Rebuilt visualization to explain the synthesis process rather than only output:
#       A Poisson waiting-time realizations (lambda*IOI, expected mean 1)
#       B actual randomized grain parameters (time/frequency/duration/amplitude)
#       C representative realized Hann-windowed grain kernels and M/S width mapping
#       D measured final stereo waveform only as output confirmation
#   - Added realized-rate, IOI mean/CV, grain-parameter, peak and RMS QC.
#   - Preserved the actual absolute-time carrier phase used by the synthesis;
#     Hann windows guarantee zero-valued grain boundaries without phase reset.
# ============================================================

form Poisson Point Process Synthesis v0.6
    optionmenu Preset 1
        option Custom
        option Sparse Ambience
        option Dense Texture
        option Rhythmic Pulse
        option Wide Stereo Field
        option Ascending Shimmer
        option Granular Cloud
        option Metallic Rain

    positive Duration_s 10.0
    positive Left_event_rate 8.0
    positive Right_event_rate 8.0
    positive Left_base_freq_Hz 120
    positive Right_base_freq_Hz 120
    real Stereo_width 1.0 (= 0 mono, 1 original stereo)

    boolean Edit_details 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---------------------------------------------------------------------------
# ADVANCED DEFAULTS
# ---------------------------------------------------------------------------
sample_rate_Hz = 44100
random_seed = 0
left_freq_spread_Hz = 200
right_freq_spread_Hz = 200
left_grain_dur_s = 0.1
right_grain_dur_s = 0.1
left_grain_spread_s = 0.05
right_grain_spread_s = 0.05
left_amplitude = 0.6
right_amplitude = 0.6

# === Apply Presets ===
preset_name$ = "Custom"

if preset = 2
    # Sparse Ambience
    left_event_rate = 3.0
    right_event_rate = 2.5
    left_base_freq_Hz = 80
    right_base_freq_Hz = 100
    left_freq_spread_Hz = 150
    right_freq_spread_Hz = 180
    left_grain_dur_s = 0.15
    right_grain_dur_s = 0.18
    left_grain_spread_s = 0.08
    right_grain_spread_s = 0.09
    left_amplitude = 0.5
    right_amplitude = 0.5
    stereo_width = 1.0
    preset_name$ = "SparseAmbience"
    
elsif preset = 3
    # Dense Texture
    left_event_rate = 25.0
    right_event_rate = 22.0
    left_base_freq_Hz = 200
    right_base_freq_Hz = 220
    left_freq_spread_Hz = 400
    right_freq_spread_Hz = 380
    left_grain_dur_s = 0.05
    right_grain_dur_s = 0.06
    left_grain_spread_s = 0.02
    right_grain_spread_s = 0.025
    left_amplitude = 0.4
    right_amplitude = 0.4
    stereo_width = 0.8
    preset_name$ = "DenseTexture"
    
elsif preset = 4
    # Rhythmic Pulse
    left_event_rate = 12.0
    right_event_rate = 12.0
    left_base_freq_Hz = 100
    right_base_freq_Hz = 105
    left_freq_spread_Hz = 50
    right_freq_spread_Hz = 55
    left_grain_dur_s = 0.08
    right_grain_dur_s = 0.08
    left_grain_spread_s = 0.01
    right_grain_spread_s = 0.01
    left_amplitude = 0.7
    right_amplitude = 0.7
    stereo_width = 0.3
    preset_name$ = "RhythmicPulse"
    
elsif preset = 5
    # Wide Stereo Field
    left_event_rate = 10.0
    right_event_rate = 10.0
    left_base_freq_Hz = 150
    right_base_freq_Hz = 450
    left_freq_spread_Hz = 100
    right_freq_spread_Hz = 300
    left_grain_dur_s = 0.12
    right_grain_dur_s = 0.09
    left_grain_spread_s = 0.05
    right_grain_spread_s = 0.04
    left_amplitude = 0.6
    right_amplitude = 0.6
    stereo_width = 1.0
    preset_name$ = "WideStereo"
    
elsif preset = 6
    # Ascending Shimmer
    left_event_rate = 18.0
    right_event_rate = 16.0
    left_base_freq_Hz = 300
    right_base_freq_Hz = 600
    left_freq_spread_Hz = 500
    right_freq_spread_Hz = 800
    left_grain_dur_s = 0.04
    right_grain_dur_s = 0.03
    left_grain_spread_s = 0.01
    right_grain_spread_s = 0.01
    left_amplitude = 0.45
    right_amplitude = 0.45
    stereo_width = 0.9
    preset_name$ = "AscendingShimmer"
    
elsif preset = 7
    # Granular Cloud
    left_event_rate = 35.0
    right_event_rate = 32.0
    left_base_freq_Hz = 400
    right_base_freq_Hz = 380
    left_freq_spread_Hz = 600
    right_freq_spread_Hz = 620
    left_grain_dur_s = 0.03
    right_grain_dur_s = 0.035
    left_grain_spread_s = 0.015
    right_grain_spread_s = 0.018
    left_amplitude = 0.35
    right_amplitude = 0.35
    stereo_width = 0.85
    preset_name$ = "GranularCloud"
    
elsif preset = 8
    # Metallic Rain
    left_event_rate = 20.0
    right_event_rate = 18.0
    left_base_freq_Hz = 800
    right_base_freq_Hz = 1200
    left_freq_spread_Hz = 1000
    right_freq_spread_Hz = 1500
    left_grain_dur_s = 0.02
    right_grain_dur_s = 0.025
    left_grain_spread_s = 0.008
    right_grain_spread_s = 0.01
    left_amplitude = 0.4
    right_amplitude = 0.4
    stereo_width = 1.0
    preset_name$ = "MetallicRain"
endif

# ---------------------------------------------------------------------------
# OPTIONAL COMPACT DETAILS PAGE
# ---------------------------------------------------------------------------
if edit_details
    beginPause: "Poisson Point Process v0.6 - Grain / Reproducibility Details"
        integer: "Sample rate (Hz)", sample_rate_Hz
        integer: "Random seed (0 = unpredictable)", random_seed
        real: "Left frequency spread (Hz)", left_freq_spread_Hz
        real: "Right frequency spread (Hz)", right_freq_spread_Hz
        positive: "Left mean grain duration (s)", left_grain_dur_s
        positive: "Right mean grain duration (s)", right_grain_dur_s
        real: "Left grain-duration spread (s)", left_grain_spread_s
        real: "Right grain-duration spread (s)", right_grain_spread_s
        positive: "Left nominal amplitude", left_amplitude
        positive: "Right nominal amplitude", right_amplitude
    endPause: "Run", 1
endif

# === Validation and derived limits ===
if sample_rate_Hz < 1000
    exitScript: "Sample_rate_Hz must be at least 1000 Hz."
endif
if stereo_width < 0 or stereo_width > 1
    exitScript: "Stereo_width must be between 0 (mono) and 1 (original stereo)."
endif
if random_seed < 0
    exitScript: "Random_seed must be 0 (random) or a positive integer."
endif
if left_freq_spread_Hz < 0 or right_freq_spread_Hz < 0
    exitScript: "Frequency spreads must be zero or positive."
endif
if left_grain_spread_s < 0 or right_grain_spread_s < 0
    exitScript: "Grain-duration spreads must be zero or positive."
endif
if left_grain_dur_s - left_grain_spread_s / 2 <= 0 or right_grain_dur_s - right_grain_spread_s / 2 <= 0
    exitScript: "Each mean grain duration must be greater than half its duration spread so every randomized grain remains positive."
endif
if left_amplitude <= 0 or right_amplitude <= 0
    exitScript: "Nominal amplitudes must be greater than zero."
endif

nyquist_Hz = sample_rate_Hz / 2
safeFreqMax_Hz = 0.95 * nyquist_Hz

leftRequestedMin_Hz = left_base_freq_Hz - left_freq_spread_Hz / 2
leftRequestedMax_Hz = left_base_freq_Hz + left_freq_spread_Hz / 2
rightRequestedMin_Hz = right_base_freq_Hz - right_freq_spread_Hz / 2
rightRequestedMax_Hz = right_base_freq_Hz + right_freq_spread_Hz / 2

leftFreqMin_Hz = max(0.1, leftRequestedMin_Hz)
leftFreqMax_Hz = min(safeFreqMax_Hz, leftRequestedMax_Hz)
rightFreqMin_Hz = max(0.1, rightRequestedMin_Hz)
rightFreqMax_Hz = min(safeFreqMax_Hz, rightRequestedMax_Hz)

if leftFreqMax_Hz < leftFreqMin_Hz
    exitScript: "Left frequency range does not intersect the synthesis centre-frequency band (0.1 Hz to 95% of Nyquist)."
endif
if rightFreqMax_Hz < rightFreqMin_Hz
    exitScript: "Right frequency range does not intersect the synthesis centre-frequency band (0.1 Hz to 95% of Nyquist)."
endif

useFixedSeed = random_seed > 0
if useFixedSeed
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
endif

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi
grainsPerChunk = 25

# === Info ===
writeInfoLine: "=== Poisson Point Process Synthesis ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", duration_s, " s"
appendInfoLine: "Left: ", left_event_rate, " events/s, ", fixed$(leftFreqMin_Hz, 1), "..", fixed$(leftFreqMax_Hz, 1), " Hz"
appendInfoLine: "Right: ", right_event_rate, " events/s, ", fixed$(rightFreqMin_Hz, 1), "..", fixed$(rightFreqMax_Hz, 1), " Hz"
appendInfoLine: "Stereo width: ", fixed$(stereo_width, 2)
appendInfoLine: "Grains L/R: mean duration ", fixed$(left_grain_dur_s, 4), "/", fixed$(right_grain_dur_s, 4), " s; frequency spread ", fixed$(left_freq_spread_Hz, 1), "/", fixed$(right_freq_spread_Hz, 1), " Hz"
if leftFreqMin_Hz <> leftRequestedMin_Hz or leftFreqMax_Hz <> leftRequestedMax_Hz or rightFreqMin_Hz <> rightRequestedMin_Hz or rightFreqMax_Hz <> rightRequestedMax_Hz
    appendInfoLine: "Note: requested frequency range was truncated so grain centre frequencies stay within 0.1 Hz..95% Nyquist."
endif
if useFixedSeed
    appendInfoLine: "Random seed: ", random_seed, " (reproducible)"
endif
appendInfoLine: ""

# ============================================================
# LEFT CHANNEL
# ============================================================
appendInfoLine: "Processing LEFT channel..."

Create Poisson process: "poisson_L_" + uid$, 0, duration_s, left_event_rate
poissonLeft = selected("PointProcess")

nPointsLeft = Get number of points
appendInfoLine: "  Generated ", nPointsLeft, " Poisson events"

# Store grain parameters
for p to nPointsLeft
    selectObject: poissonLeft
    grainTimeL[p] = Get time from index: p
    if leftFreqMax_Hz > leftFreqMin_Hz
        grainFreqL[p] = randomUniform(leftFreqMin_Hz, leftFreqMax_Hz)
    else
        grainFreqL[p] = leftFreqMin_Hz
    endif
    grainDurL[p] = left_grain_dur_s + left_grain_spread_s * (randomUniform(0, 1) - 0.5)
    grainDurL[p] = max(0.01, grainDurL[p])
    grainAmpL[p] = left_amplitude * (0.7 + 0.3 * randomUniform(0, 1))
    
    if grainTimeL[p] + grainDurL[p] > duration_s
        grainDurL[p] = duration_s - grainTimeL[p]
    endif
endfor

nRenderedLeft = 0
for p to nPointsLeft
    if grainDurL[p] > 0.005
        nRenderedLeft = nRenderedLeft + 1
    endif
endfor

# Left-process QC: complete arrival intervals only (the final censored tail is excluded).
realizedLeftRate = nPointsLeft / duration_s
leftMeanIoi = 0
leftCvIoi = 0
leftNormMean = 0
leftMeanFreq = 0
leftMeanDur = 0
leftMeanAmp = 0
leftMinFreqActual = leftFreqMin_Hz
leftMaxFreqActual = leftFreqMax_Hz
if nPointsLeft > 0
    .sumIoi = 0
    .sumSqIoi = 0
    .sumFreq = 0
    .sumDur = 0
    .sumAmp = 0
    .prevT = 0
    leftMinFreqActual = grainFreqL[1]
    leftMaxFreqActual = grainFreqL[1]
    for p to nPointsLeft
        .ioi = grainTimeL[p] - .prevT
        leftIoi[p] = .ioi
        leftNormIoi[p] = left_event_rate * .ioi
        .sumIoi = .sumIoi + .ioi
        .sumSqIoi = .sumSqIoi + .ioi * .ioi
        .sumFreq = .sumFreq + grainFreqL[p]
        .sumDur = .sumDur + grainDurL[p]
        .sumAmp = .sumAmp + grainAmpL[p]
        leftMinFreqActual = min(leftMinFreqActual, grainFreqL[p])
        leftMaxFreqActual = max(leftMaxFreqActual, grainFreqL[p])
        .prevT = grainTimeL[p]
    endfor
    leftMeanIoi = .sumIoi / nPointsLeft
    leftNormMean = left_event_rate * leftMeanIoi
    leftMeanFreq = .sumFreq / nPointsLeft
    leftMeanDur = .sumDur / nPointsLeft
    leftMeanAmp = .sumAmp / nPointsLeft
    if nPointsLeft > 1 and leftMeanIoi > 0
        .varIoi = max(0, .sumSqIoi / nPointsLeft - leftMeanIoi * leftMeanIoi)
        leftCvIoi = sqrt(.varIoi) / leftMeanIoi
    endif
endif
appendInfoLine: "  Realized left rate: ", fixed$(realizedLeftRate, 3), "/s"
if nPointsLeft > 0
    appendInfoLine: "  Left mean IOI: ", fixed$(leftMeanIoi, 4), " s (expected ", fixed$(1/left_event_rate, 4), " s)"
endif
if nPointsLeft > 1
    appendInfoLine: "  Left IOI CV: ", fixed$(leftCvIoi, 3), " (Poisson expectation approx. 1)"
endif

# Create left channel sound
leftSound = Create Sound from formula: "left_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"

# Chunked synthesis
nChunksL = ceiling(nPointsLeft / grainsPerChunk)

for chunk to nChunksL
    startGrain = (chunk - 1) * grainsPerChunk + 1
    endGrain = min(chunk * grainsPerChunk, nPointsLeft)
    
    chunkFormula$ = ""
    
    for g from startGrain to endGrain
        if grainDurL[g] > 0.005
            t$ = fixed$(grainTimeL[g], 6)
            d$ = fixed$(grainDurL[g], 6)
            f$ = fixed$(grainFreqL[g], 2)
            a$ = fixed$(grainAmpL[g], 4)
            
            # Grain: amplitude * sine * Hann window
            grainTerm$ = "if x >= " + t$ + " and x < " + t$ + " + " + d$ + " then " + a$ + " * sin(twoPi * " + f$ + " * x) * (1 - cos(twoPi * (x - " + t$ + ") / " + d$ + ")) / 2 else 0 fi"
            
            if chunkFormula$ = ""
                chunkFormula$ = grainTerm$
            else
                chunkFormula$ = chunkFormula$ + " + " + grainTerm$
            endif
        endif
    endfor
    
    if chunkFormula$ <> ""
        selectObject: leftSound
        Formula: "self + (" + chunkFormula$ + ")"
    endif
    
    if chunk mod 5 = 0
        appendInfoLine: "  Left chunk ", chunk, "/", nChunksL
    endif
endfor

removeObject: poissonLeft

# ============================================================
# RIGHT CHANNEL
# ============================================================
appendInfoLine: ""
appendInfoLine: "Processing RIGHT channel..."

Create Poisson process: "poisson_R_" + uid$, 0, duration_s, right_event_rate
poissonRight = selected("PointProcess")

nPointsRight = Get number of points
appendInfoLine: "  Generated ", nPointsRight, " Poisson events"

# Store grain parameters
for p to nPointsRight
    selectObject: poissonRight
    grainTimeR[p] = Get time from index: p
    if rightFreqMax_Hz > rightFreqMin_Hz
        grainFreqR[p] = randomUniform(rightFreqMin_Hz, rightFreqMax_Hz)
    else
        grainFreqR[p] = rightFreqMin_Hz
    endif
    grainDurR[p] = right_grain_dur_s + right_grain_spread_s * (randomUniform(0, 1) - 0.5)
    grainDurR[p] = max(0.01, grainDurR[p])
    grainAmpR[p] = right_amplitude * (0.7 + 0.3 * randomUniform(0, 1))
    
    if grainTimeR[p] + grainDurR[p] > duration_s
        grainDurR[p] = duration_s - grainTimeR[p]
    endif
endfor

nRenderedRight = 0
for p to nPointsRight
    if grainDurR[p] > 0.005
        nRenderedRight = nRenderedRight + 1
    endif
endfor

# Right-process QC.
realizedRightRate = nPointsRight / duration_s
rightMeanIoi = 0
rightCvIoi = 0
rightNormMean = 0
rightMeanFreq = 0
rightMeanDur = 0
rightMeanAmp = 0
rightMinFreqActual = rightFreqMin_Hz
rightMaxFreqActual = rightFreqMax_Hz
if nPointsRight > 0
    .sumIoi = 0
    .sumSqIoi = 0
    .sumFreq = 0
    .sumDur = 0
    .sumAmp = 0
    .prevT = 0
    rightMinFreqActual = grainFreqR[1]
    rightMaxFreqActual = grainFreqR[1]
    for p to nPointsRight
        .ioi = grainTimeR[p] - .prevT
        rightIoi[p] = .ioi
        rightNormIoi[p] = right_event_rate * .ioi
        .sumIoi = .sumIoi + .ioi
        .sumSqIoi = .sumSqIoi + .ioi * .ioi
        .sumFreq = .sumFreq + grainFreqR[p]
        .sumDur = .sumDur + grainDurR[p]
        .sumAmp = .sumAmp + grainAmpR[p]
        rightMinFreqActual = min(rightMinFreqActual, grainFreqR[p])
        rightMaxFreqActual = max(rightMaxFreqActual, grainFreqR[p])
        .prevT = grainTimeR[p]
    endfor
    rightMeanIoi = .sumIoi / nPointsRight
    rightNormMean = right_event_rate * rightMeanIoi
    rightMeanFreq = .sumFreq / nPointsRight
    rightMeanDur = .sumDur / nPointsRight
    rightMeanAmp = .sumAmp / nPointsRight
    if nPointsRight > 1 and rightMeanIoi > 0
        .varIoi = max(0, .sumSqIoi / nPointsRight - rightMeanIoi * rightMeanIoi)
        rightCvIoi = sqrt(.varIoi) / rightMeanIoi
    endif
endif
appendInfoLine: "  Realized right rate: ", fixed$(realizedRightRate, 3), "/s"
if nPointsRight > 0
    appendInfoLine: "  Right mean IOI: ", fixed$(rightMeanIoi, 4), " s (expected ", fixed$(1/right_event_rate, 4), " s)"
endif
if nPointsRight > 1
    appendInfoLine: "  Right IOI CV: ", fixed$(rightCvIoi, 3), " (Poisson expectation approx. 1)"
endif

# Create right channel sound
rightSound = Create Sound from formula: "right_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"

# Chunked synthesis
nChunksR = ceiling(nPointsRight / grainsPerChunk)

for chunk to nChunksR
    startGrain = (chunk - 1) * grainsPerChunk + 1
    endGrain = min(chunk * grainsPerChunk, nPointsRight)
    
    chunkFormula$ = ""
    
    for g from startGrain to endGrain
        if grainDurR[g] > 0.005
            t$ = fixed$(grainTimeR[g], 6)
            d$ = fixed$(grainDurR[g], 6)
            f$ = fixed$(grainFreqR[g], 2)
            a$ = fixed$(grainAmpR[g], 4)
            
            grainTerm$ = "if x >= " + t$ + " and x < " + t$ + " + " + d$ + " then " + a$ + " * sin(twoPi * " + f$ + " * x) * (1 - cos(twoPi * (x - " + t$ + ") / " + d$ + ")) / 2 else 0 fi"
            
            if chunkFormula$ = ""
                chunkFormula$ = grainTerm$
            else
                chunkFormula$ = chunkFormula$ + " + " + grainTerm$
            endif
        endif
    endfor
    
    if chunkFormula$ <> ""
        selectObject: rightSound
        Formula: "self + (" + chunkFormula$ + ")"
    endif
    
    if chunk mod 5 = 0
        appendInfoLine: "  Right chunk ", chunk, "/", nChunksR
    endif
endfor

removeObject: poissonRight

# ============================================================
# COMBINE TO STEREO
# ============================================================
appendInfoLine: ""
appendInfoLine: "Combining to stereo..."

selectObject: leftSound
plusObject: rightSound
outputSound = Combine to stereo
Rename: "poisson_" + preset_name$

removeObject: leftSound, rightSound

# Apply exact mid/side stereo width.
# M=(L+R)/2, S=(L-R)/2; L'=M+width*S, R'=M-width*S.
# This preserves the original image at width=1 and gives true mono at width=0.
if stereo_width < 1.0
    selectObject: outputSound
    Copy: "preWidth_" + uid$
    preWidth = selected("Sound")
    selectObject: outputSound
    Formula: "if row = 1 then 0.5 * ((1 + stereo_width) * object[preWidth, 1, col] + (1 - stereo_width) * object[preWidth, 2, col]) else 0.5 * ((1 - stereo_width) * object[preWidth, 1, col] + (1 + stereo_width) * object[preWidth, 2, col]) fi"
    removeObject: preWidth
endif

# === Fade In/Out ===
fadeIn_s = min(0.02, duration_s / 2)
fadeOut_s = min(0.05, duration_s / 2)
selectObject: outputSound
Formula: "if x < fadeIn_s then self * (x / fadeIn_s) else self fi"
Formula: "if x > duration_s - fadeOut_s then self * ((duration_s - x) / fadeOut_s) else self fi"

# === Normalize / measured output QC ===
# A Poisson realization can contain zero events, especially for very short/low-rate settings.
selectObject: outputSound
preNormPeak = Get absolute extremum: 0, 0, "None"
preNormRMS = Get root-mean-square: 0, 0
if nPointsLeft + nPointsRight > 0 and preNormPeak > 0
    Scale peak: 0.9
else
    appendInfoLine: "Warning: this Poisson realization contained no nonzero grain output; output is silent."
endif
selectObject: outputSound
finalPeak = Get absolute extremum: 0, 0, "None"
finalRMS = Get root-mean-square: 0, 0
appendInfoLine: "Output pre-normalization peak/RMS: ", fixed$(preNormPeak, 4), " / ", fixed$(preNormRMS, 4)
appendInfoLine: "Output final peak/RMS: ", fixed$(finalPeak, 4), " / ", fixed$(finalRMS, 4)

# Do not leave Praat's global RNG in deterministic mode after a reproducible run.
if useFixedSeed
    random_initializeSafelyAndUnpredictably ()
endif

# === Visualization ===
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."
    @drawVisualization
endif

# === Play ===
if play_result
    selectObject: outputSound
    Play
endif

# === Final Selection ===
selectObject: outputSound

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Total events: ", nPointsLeft + nPointsRight, " (L: ", nPointsLeft, ", R: ", nPointsRight, ")"
appendInfoLine: "Created: ", selected$("Sound")

# ==============================================================================
# Procedure: drawVisualization
# ==============================================================================
procedure drawVisualization

    .left = 0.78
    .right = 7.58
    .bg$ = "{0.975,0.975,0.978}"
    .grid$ = "{0.80,0.80,0.82}"
    .blue$ = "{0.18,0.43,0.72}"
    .orange$ = "{0.76,0.38,0.18}"
    .green$ = "{0.25,0.58,0.38}"
    .purple$ = "{0.52,0.30,0.62}"
    .grey$ = "{0.42,0.42,0.45}"

    Erase all

    selectObject: outputSound
    .dur = Get total duration

    if random_seed > 0
        .seed$ = "seed " + string$(random_seed)
    else
        .seed$ = "unpredictable seed"
    endif

    # -----------------------------------------------------------------------
    # HEADER / PROCESS FLOW
    # -----------------------------------------------------------------------
    Select inner viewport: 0.20,7.80,0.05,0.32
    Axes: 0,1,0,1
    Font size: 12
    Colour: "Black"
    Text: 0.5,"centre",0.55,"half", "POISSON POINT PROCESS SYNTHESIS | " + preset_name$

    Select inner viewport: 0.35,7.65,0.36,0.68
    Axes: 0,1,0,1
    Font size: 6
    Colour: .grey$
    Text: 0.5,"centre",0.70,"half", "independent L/R Poisson clocks | L " + fixed$(left_event_rate,2) + "/s | R " + fixed$(right_event_rate,2) + "/s | " + .seed$
    Text: 0.5,"centre",0.20,"half", "rates -> Poisson waiting times -> random f/D/A -> Hann-windowed grains -> channel sums -> M/S width -> mix"

    # -----------------------------------------------------------------------
    # PANEL A: POISSON WAITING-TIME REALIZATION
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,0.78,0.98
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half", "A  POISSON CLOCKS | actual normalized waiting times; theoretical mean = 1"

    Select inner viewport: .left,.right,1.01,1.14
    Axes: 0,1,0,1
    Font size: 5
    Colour: .grey$
    Text: 0.01,"left",0.72,"half", "Poisson rule: p(dt)=lambda exp(-lambda dt); expected normalized waiting time lambda dt = 1"
    Text: 0.01,"left",0.22,"half", "blue L | orange R | each stem is one realized complete waiting time"

    .ratioMax = 4
    for .p to nPointsLeft
        .ratioMax = max(.ratioMax,leftNormIoi[.p])
    endfor
    for .p to nPointsRight
        .ratioMax = max(.ratioMax,rightNormIoi[.p])
    endfor
    .ratioMax = 1.08*.ratioMax

    Select inner viewport: .left,.right,1.16,2.08
    Axes: 0,duration_s,0,.ratioMax
    Paint rectangle: .bg$,0,duration_s,0,.ratioMax
    Colour: .grid$
    Dotted line
    Draw line: 0,1,duration_s,1
    Plain line

    .stepL = max(1,ceiling(max(1,nPointsLeft)/600))
    for .p to nPointsLeft
        if ((.p-1) mod .stepL)=0
            Colour: .blue$
            Draw line: grainTimeL[.p],0,grainTimeL[.p],leftNormIoi[.p]
            Paint circle (mm): .blue$,grainTimeL[.p],leftNormIoi[.p],1.0
        endif
    endfor
    .stepR = max(1,ceiling(max(1,nPointsRight)/600))
    for .p to nPointsRight
        if ((.p-1) mod .stepR)=0
            Colour: .orange$
            Draw line: grainTimeR[.p],0,grainTimeR[.p],rightNormIoi[.p]
            Paint circle (mm): .orange$,grainTimeR[.p],rightNormIoi[.p],0.9
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Marks left: 4,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","rate x IOI"
    Text bottom: "yes","Event time (s)"

    # -----------------------------------------------------------------------
    # PANEL B: RANDOM GRAIN-PARAMETER ASSIGNMENT
    # x = onset, y = centre frequency, horizontal segment = duration,
    # marker radius = realized amplitude relative to nominal channel amplitude.
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,2.22,2.42
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half", "B  RANDOM GRAIN PARAMETERS | onset -> centre frequency, duration and amplitude"

    Select inner viewport: .left,.right,2.44,2.56
    Axes: 0,1,0,1
    Font size: 5
    Colour: .grey$
    Text: 0.5,"centre",0.48,"half", "y=f | line length=D | circle size=A | plotted grains are the actual draws rendered after end clipping (>5 ms)"

    .fMin = min(leftFreqMin_Hz,rightFreqMin_Hz)
    .fMax = max(leftFreqMax_Hz,rightFreqMax_Hz)
    .fPad = max(10,0.06*(.fMax-.fMin))
    .plotFMin = max(0,.fMin-.fPad)
    .plotFMax = min(safeFreqMax_Hz,.fMax+.fPad)
    if .plotFMax <= .plotFMin
        .plotFMax = .plotFMin + 1
    endif

    Select inner viewport: .left,.right,2.58,3.52
    Axes: 0,duration_s,.plotFMin,.plotFMax
    Paint rectangle: .bg$,0,duration_s,.plotFMin,.plotFMax
    Colour: .grid$
    Dotted line
    Draw line: 0,left_base_freq_Hz,duration_s,left_base_freq_Hz
    Draw line: 0,right_base_freq_Hz,duration_s,right_base_freq_Hz
    Plain line

    .stepL = max(1,ceiling(max(1,nPointsLeft)/700))
    for .p to nPointsLeft
        if ((.p-1) mod .stepL)=0 and grainDurL[.p] > 0.005
            .t0 = grainTimeL[.p]
            .t1 = min(duration_s,.t0+grainDurL[.p])
            .r = 0.55 + 0.75*grainAmpL[.p]/left_amplitude
            Colour: .blue$
            Draw line: .t0,grainFreqL[.p],.t1,grainFreqL[.p]
            Paint circle (mm): .blue$,.t0,grainFreqL[.p],.r
        endif
    endfor
    .stepR = max(1,ceiling(max(1,nPointsRight)/700))
    for .p to nPointsRight
        if ((.p-1) mod .stepR)=0 and grainDurR[.p] > 0.005
            .t0 = grainTimeR[.p]
            .t1 = min(duration_s,.t0+grainDurR[.p])
            .r = 0.55 + 0.75*grainAmpR[.p]/right_amplitude
            Colour: .orange$
            Draw line: .t0,grainFreqR[.p],.t1,grainFreqR[.p]
            Paint circle (mm): .orange$,.t0,grainFreqR[.p],.r
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Marks left: 4,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","Centre frequency (Hz)"
    Text bottom: "yes","Event time (s)"

    # -----------------------------------------------------------------------
    # PANEL C: REALIZED GRAIN KERNELS -> SUM -> M/S WIDTH
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,3.66,3.86
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half", "C  GRAIN KERNEL -> CHANNEL SUM -> M/S WIDTH | representative realized L/R grains"

    Select inner viewport: .left,.right,3.88,4.02
    Axes: 0,1,0,1
    Font size: 5
    Colour: .grey$
    Text: 0.5,"centre",0.70,"half", "g(tau)=A sin(2 pi f (tevent+tau)) 0.5[1-cos(2 pi tau/D)] | tau in [0,D)"
    Text: 0.5,"centre",0.18,"half", "Lraw=sum gL | Rraw=sum gR | M=(Lraw+Rraw)/2, S=(Lraw-Rraw)/2 -> L'=M+wS, R'=M-wS"

    # Representative left grain: first event with a drawable duration.
    .leftRep = 0
    for .p to nPointsLeft
        if .leftRep=0 and grainDurL[.p] > 0.005
            .leftRep = .p
        endif
    endfor
    Select inner viewport: .left,3.92,4.08,4.90
    if .leftRep > 0
        .tEvent = grainTimeL[.leftRep]
        .d = grainDurL[.leftRep]
        .f = grainFreqL[.leftRep]
        .amp = grainAmpL[.leftRep]
        Axes: 0,1000*.d,-1.08*.amp,1.08*.amp
        Paint rectangle: .bg$,0,1000*.d,-1.08*.amp,1.08*.amp
        Colour: .grid$
        Dotted line
        Draw line: 0,0,1000*.d,0
        Plain line
        .prevMs = 0
        .prevY = 0
        .prevEnv = 0
        .nPts = 260
        for .k from 1 to .nPts
            .tau = .k/.nPts*.d
            .ms = 1000*.tau
            .env = .amp*0.5*(1-cos(twoPi*.tau/.d))
            .y = .env*sin(twoPi*.f*(.tEvent+.tau))
            Colour: .blue$
            Draw line: .prevMs,.prevY,.ms,.y
            Colour: .grey$
            Dashed line
            Draw line: .prevMs,.prevEnv,.ms,.env
            Draw line: .prevMs,-.prevEnv,.ms,-.env
            Plain line
            .prevMs = .ms
            .prevY = .y
            .prevEnv = .env
        endfor
        Colour: "Black"
        Draw inner box
        Marks left: 3,"yes","yes","no"
        Marks bottom: 4,"yes","yes","no"
        Font size: 5
        Text left: "yes","L amp"
        Text bottom: "yes","ms"
    else
        Axes: 0,1,0,1
        Paint rectangle: .bg$,0,1,0,1
        Colour: .grey$
        Text: 0.5,"centre",0.5,"half","No drawable L grain in this realization"
        Colour: "Black"
        Draw inner box
    endif

    Select inner viewport: .left,3.92,4.00,4.10
    Axes: 0,1,0,1
    Font size: 5
    Colour: .grey$
    if .leftRep > 0
        Text: 0.5,"centre",0.5,"half", "L example: f=" + fixed$(grainFreqL[.leftRep],1) + " Hz | D=" + fixed$(1000*grainDurL[.leftRep],1) + " ms | A=" + fixed$(grainAmpL[.leftRep],3)
    endif

    # Representative right grain.
    .rightRep = 0
    for .p to nPointsRight
        if .rightRep=0 and grainDurR[.p] > 0.005
            .rightRep = .p
        endif
    endfor
    Select inner viewport: 4.20,.right,4.08,4.90
    if .rightRep > 0
        .tEvent = grainTimeR[.rightRep]
        .d = grainDurR[.rightRep]
        .f = grainFreqR[.rightRep]
        .amp = grainAmpR[.rightRep]
        Axes: 0,1000*.d,-1.08*.amp,1.08*.amp
        Paint rectangle: .bg$,0,1000*.d,-1.08*.amp,1.08*.amp
        Colour: .grid$
        Dotted line
        Draw line: 0,0,1000*.d,0
        Plain line
        .prevMs = 0
        .prevY = 0
        .prevEnv = 0
        .nPts = 260
        for .k from 1 to .nPts
            .tau = .k/.nPts*.d
            .ms = 1000*.tau
            .env = .amp*0.5*(1-cos(twoPi*.tau/.d))
            .y = .env*sin(twoPi*.f*(.tEvent+.tau))
            Colour: .orange$
            Draw line: .prevMs,.prevY,.ms,.y
            Colour: .grey$
            Dashed line
            Draw line: .prevMs,.prevEnv,.ms,.env
            Draw line: .prevMs,-.prevEnv,.ms,-.env
            Plain line
            .prevMs = .ms
            .prevY = .y
            .prevEnv = .env
        endfor
        Colour: "Black"
        Draw inner box
        Marks left: 3,"yes","yes","no"
        Marks bottom: 4,"yes","yes","no"
        Font size: 5
        Text left: "yes","R amp"
        Text bottom: "yes","ms"
    else
        Axes: 0,1,0,1
        Paint rectangle: .bg$,0,1,0,1
        Colour: .grey$
        Text: 0.5,"centre",0.5,"half","No drawable R grain in this realization"
        Colour: "Black"
        Draw inner box
    endif

    Select inner viewport: 4.20,.right,4.00,4.10
    Axes: 0,1,0,1
    Font size: 5
    Colour: .grey$
    if .rightRep > 0
        Text: 0.5,"centre",0.5,"half", "R example: f=" + fixed$(grainFreqR[.rightRep],1) + " Hz | D=" + fixed$(1000*grainDurR[.rightRep],1) + " ms | A=" + fixed$(grainAmpR[.rightRep],3)
    endif

    # -----------------------------------------------------------------------
    # PANEL D: MEASURED OUTPUT CONFIRMATION
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,5.04,5.24
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half", "D  MEASURED OUTPUT | post-width, post-fade, normalized waveform (confirmation, not the model)"

    Select inner viewport: .left,.right,5.32,5.76
    Axes: 0,.dur,-1,1
    Paint rectangle: .bg$,0,.dur,-1,1
    selectObject: outputSound
    Extract one channel: 1
    .leftViz = selected("Sound")
    Colour: .green$
    Draw: 0,0,-1,1,"no","Curve"
    removeObject: .leftViz
    Select inner viewport: .left,.right,5.32,5.76
    Axes: 0,.dur,-1,1
    Colour: "Black"
    Draw inner box
    Font size: 5
    Text left: "yes","L"

    Select inner viewport: .left,.right,5.86,6.30
    Axes: 0,.dur,-1,1
    Paint rectangle: .bg$,0,.dur,-1,1
    selectObject: outputSound
    Extract one channel: 2
    .rightViz = selected("Sound")
    Colour: .purple$
    Draw: 0,0,-1,1,"no","Curve"
    removeObject: .rightViz
    Select inner viewport: .left,.right,5.86,6.30
    Axes: 0,.dur,-1,1
    Colour: "Black"
    Draw inner box
    Marks bottom: 5,"yes","yes","no"
    Font size: 5
    Text left: "yes","R"
    Text bottom: "yes","Time (s)"

    # -----------------------------------------------------------------------
    # PROCESS / QC SUMMARY
    # -----------------------------------------------------------------------
    Select inner viewport: 0.50,7.50,6.50,7.78
    Axes: 0,1,0,1
    Paint rectangle: "{0.93,0.93,0.935}",0,1,0,1
    Font size: 6
    Colour: "{0.25,0.25,0.25}"
    Text: 0.02,"left",0.82,"half", "MODEL | independent homogeneous Poisson processes for L/R; random f, D and A per event"

    if nPointsLeft > 1
        .leftCv$ = fixed$(leftCvIoi,2)
    else
        .leftCv$ = "n/a"
    endif
    if nPointsRight > 1
        .rightCv$ = fixed$(rightCvIoi,2)
    else
        .rightCv$ = "n/a"
    endif
    Text: 0.02,"left",0.62,"half", "POISSON QC | target/realized L " + fixed$(left_event_rate,2) + "/" + fixed$(realizedLeftRate,2) + "/s, R " + fixed$(right_event_rate,2) + "/" + fixed$(realizedRightRate,2) + "/s | IOI CV " + .leftCv$ + "/" + .rightCv$

    if nPointsLeft > 0
        .lGrain$ = fixed$(leftMeanFreq,0) + " Hz, " + fixed$(1000*leftMeanDur,1) + " ms, A " + fixed$(leftMeanAmp,3)
    else
        .lGrain$ = "n/a"
    endif
    if nPointsRight > 0
        .rGrain$ = fixed$(rightMeanFreq,0) + " Hz, " + fixed$(1000*rightMeanDur,1) + " ms, A " + fixed$(rightMeanAmp,3)
    else
        .rGrain$ = "n/a"
    endif
    Text: 0.02,"left",0.42,"half", "GRAIN QC | stored means L " + .lGrain$ + " | R " + .rGrain$ + " | rendered L/R " + string$(nRenderedLeft) + "/" + string$(nRenderedRight) + " | Hann boundaries = 0"

    Text: 0.02,"left",0.22,"half", "STEREO | M/S width w=" + fixed$(stereo_width,2) + " | centre-frequency guard <= " + fixed$(safeFreqMax_Hz,0) + " Hz (95% Nyquist) | sr " + string$(sample_rate_Hz) + " Hz"
    Text: 0.02,"left",0.06,"half", "OUTPUT QC | Poisson events L/R " + string$(nPointsLeft) + "/" + string$(nPointsRight) + " | final peak/RMS " + fixed$(finalPeak,3) + "/" + fixed$(finalRMS,4)

    Colour: "Black"
    Line width: 1
endproc