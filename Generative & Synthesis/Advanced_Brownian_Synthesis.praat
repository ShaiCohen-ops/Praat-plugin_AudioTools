# ============================================================
# Praat AudioTools - Advanced Brownian Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 reviewed (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Brownian motion-based synthesis with multiple layers and modes.
#   Generates evolving, organic textures through frequency random walks.
#
# Usage:
#   Run this script (no input sound required).
#   Select a preset or adjust custom parameters.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.5 reviewed:
#   - Brownian trajectory is treated explicitly as a discrete OU/Brownian process:
#       df = k(mu-f)dt + sigma*sqrt(dt)N(0,1)
#     while preserving the v0.4 preset step scale at the 200-Hz control rate.
#   - Replaced hard frequency clipping with reflective boundaries to avoid
#     artificial dwell/flattening at 30 Hz or the upper limit.
#   - Upper synthesis bound now follows sample-rate Nyquist (min(8 kHz, 0.45*Fs)).
#   - Frequency_spread_Hz now actually spaces layers in Walk, Chaos and Pulsed
#     modes; it is intentionally ignored only by Harmonics.
#   - Replaced resampling of an unwrapped phase ramp with: resample frequency
#     control -> integrate phase at audio rate. This avoids sinc-ringing of phase.
#   - Formula cross-object reads now use unique object IDs and documented object().
#   - Added reproducible Random_seed (0 = unpredictable) and restores the RNG.
#   - Fixed zero-step Chaos division, negative step/drift values, sample-rate
#     validation, fade guards and Nyquist-safe stereo filtering.
#   - Rotating stereo now uses complementary equal-power left/right panning.
#   - Visualization shows the ACTUAL Brownian trajectories used by the DSP,
#     measured spectrogram with trajectory overlay, waveform, realized frequency
#     range/step statistics and boundary-reflection QC.
#
# Changelog v0.4:
#   - Fixed preset mode labels: presets set the numeric synthesis_mode but left
#     synthesis_mode$ (and spatial_mode$) at the form default, so every preset
#     reported "Brownian Walk" in the info window and plot title regardless of
#     the actual mode. Each preset now sets synthesis_mode$; the plot derives
#     the spatial label from the numeric value.
#   - Rebuilt the visualization in the AudioTools house style (8-inch canvas,
#     title band, waveform + spectrogram, grey summary, larger fonts, black marks).
#   - Replaced the non-ASCII en-dash.
# ============================================================

form Advanced Brownian Synthesis
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Default Walk
        option Tight Knots
        option Loose Drift
        option Chaotic Swarm
        option Harmonic Bells
        option Deep Drone
        option Spectral Shimmer
        option Insect Swarm
    
    comment === Basic Settings ===
    positive Duration_s 10
    integer Sample_rate_Hz 44100
    positive Base_frequency_Hz 150
    integer Number_of_layers 4
    
    comment === Brownian Motion ===
    real Frequency_spread_Hz 100
    real Step_size 10
    boolean Enable_drift 1
    real Drift_force 0.1
    integer Random_seed 0
    comment 0 = unpredictable; positive value = reproducible trajectory
    
    comment === Synthesis Mode ===
    optionmenu Synthesis_mode 1
        option Brownian Walk
        option Brownian Chaos
        option Brownian Harmonics
        option Pulsed Brownian
    
    comment === Output ===
    real Fade_time_s 2
    optionmenu Spatial_mode 1
        option Mono
        option Stereo Wide
        option Rotating
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
preset_name$ = "Custom"

if preset = 2
    duration_s = 10
    base_frequency_Hz = 150
    number_of_layers = 4
    frequency_spread_Hz = 100
    step_size = 10
    enable_drift = 1
    drift_force = 0.1
    fade_time_s = 2
    synthesis_mode = 1
    spatial_mode = 1
    synthesis_mode$ = "Brownian Walk"
    preset_name$ = "DefaultWalk"
elsif preset = 3
    duration_s = 8
    base_frequency_Hz = 200
    number_of_layers = 6
    frequency_spread_Hz = 50
    step_size = 5
    enable_drift = 1
    drift_force = 0.2
    fade_time_s = 1
    synthesis_mode = 1
    spatial_mode = 2
    synthesis_mode$ = "Brownian Walk"
    preset_name$ = "TightKnots"
elsif preset = 4
    duration_s = 15
    base_frequency_Hz = 100
    number_of_layers = 3
    frequency_spread_Hz = 200
    step_size = 20
    enable_drift = 1
    drift_force = 0.05
    fade_time_s = 3
    synthesis_mode = 1
    spatial_mode = 3
    synthesis_mode$ = "Brownian Walk"
    preset_name$ = "LooseDrift"
elsif preset = 5
    duration_s = 12
    base_frequency_Hz = 180
    number_of_layers = 8
    frequency_spread_Hz = 80
    step_size = 15
    enable_drift = 1
    drift_force = 0.15
    fade_time_s = 2
    synthesis_mode = 2
    spatial_mode = 2
    synthesis_mode$ = "Brownian Chaos"
    preset_name$ = "ChaoticSwarm"
elsif preset = 6
    duration_s = 10
    base_frequency_Hz = 220
    number_of_layers = 5
    frequency_spread_Hz = 0
    step_size = 8
    enable_drift = 1
    drift_force = 0.1
    fade_time_s = 2
    synthesis_mode = 3
    spatial_mode = 1
    synthesis_mode$ = "Brownian Harmonics"
    preset_name$ = "HarmonicBells"
elsif preset = 7
    duration_s = 20
    base_frequency_Hz = 55
    number_of_layers = 3
    frequency_spread_Hz = 20
    step_size = 3
    enable_drift = 1
    drift_force = 0.3
    fade_time_s = 5
    synthesis_mode = 1
    spatial_mode = 3
    synthesis_mode$ = "Brownian Walk"
    preset_name$ = "DeepDrone"
elsif preset = 8
    duration_s = 12
    base_frequency_Hz = 440
    number_of_layers = 6
    frequency_spread_Hz = 0
    step_size = 25
    enable_drift = 1
    drift_force = 0.08
    fade_time_s = 2
    synthesis_mode = 3
    spatial_mode = 2
    synthesis_mode$ = "Brownian Harmonics"
    preset_name$ = "SpectralShimmer"
elsif preset = 9
    duration_s = 8
    base_frequency_Hz = 800
    number_of_layers = 10
    frequency_spread_Hz = 400
    step_size = 50
    enable_drift = 1
    drift_force = 0.05
    fade_time_s = 1
    synthesis_mode = 2
    spatial_mode = 2
    synthesis_mode$ = "Brownian Chaos"
    preset_name$ = "InsectSwarm"
endif

# === Validation ===
if number_of_layers > 16
    number_of_layers = 16
endif
if number_of_layers < 1
    number_of_layers = 1
endif

if sample_rate_Hz < 8000
    exitScript: "Sample rate must be at least 8000 Hz."
endif

if step_size < 0
    step_size = abs(step_size)
endif

if drift_force < 0
    drift_force = 0
endif

if fade_time_s < 0
    fade_time_s = 0
endif
if fade_time_s > duration_s / 2
    fade_time_s = duration_s / 2
endif

if random_seed < 0
    random_seed = 0
endif

# === Constants ===
random_initializeSafelyAndUnpredictably ()
uid$ = string$(randomInteger(10000, 99999))

twoPi = 2 * pi
controlRate = 200
timeStep = 1 / controlRate

# Keep carriers comfortably below Nyquist. 0.45*Fs = 90% of Nyquist.
lowFreq = 30
highFreq = min(8000, 0.45 * sample_rate_Hz)

if base_frequency_Hz >= highFreq
    exitScript: "Base frequency is too high for this sample rate. Use a value below " + fixed$(highFreq, 1) + " Hz."
endif

# Visualization storage: at most ~420 trajectory samples per layer.
maxVizPerLayer = 420

# Realized-process QC.
globalMinFreq = highFreq
globalMaxFreq = lowFreq
sumSqAppliedStep = 0
nAppliedSteps = 0
boundaryReflections = 0
initialClampCount = 0

# === Random-state handling ===
if random_seed = 0
    random_initializeSafelyAndUnpredictably ()
    seedLabel$ = "random each run"
else
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedLabel$ = "seed " + string$(random_seed)
endif

# === Info ===
writeInfoLine: "=== Advanced Brownian Synthesis ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", duration_s, " s"
appendInfoLine: "Layers: ", number_of_layers
appendInfoLine: "Mode: ", synthesis_mode$
appendInfoLine: "Frequency domain: ", fixed$(lowFreq, 1), " .. ", fixed$(highFreq, 1), " Hz"
appendInfoLine: "Randomness: ", seedLabel$
appendInfoLine: ""

# === Create output sound ===
outputSound = Create Sound from formula: "brownian_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"

# === Process each layer ===
for layer to number_of_layers
    appendInfoLine: "Layer ", layer, "/", number_of_layers, "..."

    # ------------------------------------------------------------
    # Initial state / target / layer amplitude
    # ------------------------------------------------------------
    # Frequency_spread_Hz is layer spacing in Walk/Chaos/Pulsed.
    # Harmonics intentionally derives layers from integer multiples.
    if synthesis_mode = 1
        voiceFreq = base_frequency_Hz + (layer - 1) * frequency_spread_Hz
        stepSigmaFrame = step_size
        ampBase = 0.6 / number_of_layers
        targetFreq = voiceFreq

    elsif synthesis_mode = 2
        voiceFreq = base_frequency_Hz + (layer - 1) * frequency_spread_Hz
        stepSigmaFrame = step_size * (1 + layer * 0.5)
        ampBase = 0.7 / number_of_layers
        targetFreq = base_frequency_Hz * 2

    elsif synthesis_mode = 3
        voiceFreq = base_frequency_Hz * layer
        stepSigmaFrame = step_size * (0.5 + layer * 0.2)
        ampBase = (0.5 / number_of_layers) / layer
        targetFreq = base_frequency_Hz * layer

    else
        voiceFreq = base_frequency_Hz + (layer - 1) * frequency_spread_Hz
        stepSigmaFrame = step_size
        ampBase = 0.7 / number_of_layers
        targetFreq = base_frequency_Hz
        pulseRate = 2 + layer * 1.5
    endif

    # Clamp initial state/target once, and report that this occurred.
    unclampedInitial = voiceFreq
    voiceFreq = max(lowFreq, min(highFreq, voiceFreq))
    if voiceFreq <> unclampedInitial
        initialClampCount = initialClampCount + 1
    endif

    targetFreq = max(lowFreq, min(highFreq, targetFreq))
    vizTarget[layer] = targetFreq

    # Convert the historical per-frame step setting into a diffusion
    # coefficient, then apply sigma*sqrt(dt). At 200 Hz this preserves
    # the v0.4 step magnitude but makes the equation rate-explicit.
    diffusionHzPerSqrtS = stepSigmaFrame * sqrt(controlRate)

    # ------------------------------------------------------------
    # Create control-rate frequency and amplitude trajectories
    # ------------------------------------------------------------
    ampCtrl = Create Sound from formula: "ampCtrl_" + uid$, 1, 0, duration_s, controlRate, "0"
    freqCtrl = Create Sound from formula: "freqCtrl_" + uid$, 1, 0, duration_s, controlRate, "0"

    selectObject: ampCtrl
    nControlPoints = Get number of samples
    vizStride = max(1, ceiling(nControlPoints / maxVizPerLayer))
    vizCount[layer] = 0

    for cp to nControlPoints
        currentTime = (cp - 1) * timeStep
        previousFreq = voiceFreq

        # Brownian innovation.
        brownianStep = randomGauss(0, 1) * diffusionHzPerSqrtS * sqrt(timeStep)

        # Chaos mode adds occasional heavy-tail jumps.
        if synthesis_mode = 2
            if randomUniform(0, 1) < 0.1
                brownianStep = brownianStep * 5
            endif
        endif

        # Mean-reverting drift: discrete Ornstein-Uhlenbeck term.
        if enable_drift
            brownianStep = brownianStep + (targetFreq - voiceFreq) * drift_force * timeStep
        endif

        candidateFreq = voiceFreq + brownianStep

        # Reflect at frequency boundaries instead of hard-clipping there.
        if candidateFreq < lowFreq
            candidateFreq = lowFreq + (lowFreq - candidateFreq)
            boundaryReflections = boundaryReflections + 1
        elsif candidateFreq > highFreq
            candidateFreq = highFreq - (candidateFreq - highFreq)
            boundaryReflections = boundaryReflections + 1
        endif

        # A single very large chaos jump can cross both walls; this final
        # guard guarantees a valid carrier while reflection handles normal hits.
        voiceFreq = max(lowFreq, min(highFreq, candidateFreq))

        appliedStep = voiceFreq - previousFreq
        sumSqAppliedStep = sumSqAppliedStep + appliedStep ^ 2
        nAppliedSteps = nAppliedSteps + 1

        globalMinFreq = min(globalMinFreq, voiceFreq)
        globalMaxFreq = max(globalMaxFreq, voiceFreq)

        # Amplitude law.
        if synthesis_mode = 2
            if stepSigmaFrame > 0
                stability = exp(-abs(brownianStep) / stepSigmaFrame)
            else
                stability = 1
            endif
            voiceAmp = ampBase * stability

        elsif synthesis_mode = 4
            pulse = 0.2 + 0.8 * max(0, sin(twoPi * pulseRate * currentTime) - 0.7) / 0.3
            pulse = min(1, pulse)
            voiceAmp = ampBase * pulse

        else
            voiceAmp = ampBase * (1 - (layer - 1) / number_of_layers * 0.3)
        endif

        # Store control values.
        selectObject: ampCtrl
        Set value at sample number: 1, cp, voiceAmp

        selectObject: freqCtrl
        Set value at sample number: 1, cp, voiceFreq

        # Store a decimated copy of the ACTUAL trajectory for the Picture window.
        if cp = 1 or cp = nControlPoints or ((cp - 1) mod vizStride) = 0
            if vizCount[layer] < maxVizPerLayer
                vizCount[layer] = vizCount[layer] + 1
                vizIndex = (layer - 1) * maxVizPerLayer + vizCount[layer]
                vizTime[vizIndex] = currentTime
                vizFreq[vizIndex] = voiceFreq
            endif
        endif
    endfor

    # ------------------------------------------------------------
    # Resample controls, then integrate frequency at AUDIO RATE.
    # This avoids sinc-resampling a rapidly growing unwrapped phase ramp.
    # ------------------------------------------------------------
    selectObject: ampCtrl
    ampAudio = Resample: sample_rate_Hz, 50

    selectObject: freqCtrl
    freqAudio = Resample: sample_rate_Hz, 50

    phaseAudio = Create Sound from formula: "phaseAudio_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"

    freqIdStr$ = string$(freqAudio)
    phaseScaleStr$ = string$(twoPi / sample_rate_Hz)

    selectObject: phaseAudio
    Formula: "if col = 1 then 0 else self[col - 1] + " + phaseScaleStr$ + " * object(" + freqIdStr$ + ", x, 1) fi"

    # ------------------------------------------------------------
    # Synthesize this layer from the actual amplitude and integrated phase.
    # ------------------------------------------------------------
    ampIdStr$ = string$(ampAudio)
    phaseIdStr$ = string$(phaseAudio)

    layerSound = Create Sound from formula: "layer_" + uid$, 1, 0, duration_s, sample_rate_Hz, "object(" + ampIdStr$ + ", x, 1) * sin(object(" + phaseIdStr$ + ", x, 1))"

    # Add to output using a unique object ID.
    layerIdStr$ = string$(layerSound)
    selectObject: outputSound
    Formula: "self + object(" + layerIdStr$ + ", x, 1)"

    removeObject: ampCtrl, freqCtrl, ampAudio, freqAudio, phaseAudio, layerSound
endfor

# Restore an unpredictable RNG after a reproducible run.
if random_seed <> 0
    random_initializeSafelyAndUnpredictably ()
endif

if nAppliedSteps > 0
    realizedStepRms = sqrt(sumSqAppliedStep / nAppliedSteps)
else
    realizedStepRms = 0
endif

appendInfoLine: ""
appendInfoLine: "Realized frequency range: ", fixed$(globalMinFreq, 1), " .. ", fixed$(globalMaxFreq, 1), " Hz"
appendInfoLine: "Realized RMS control-step: ", fixed$(realizedStepRms, 2), " Hz"
appendInfoLine: "Boundary reflections: ", boundaryReflections
if initialClampCount > 0
    appendInfoLine: "WARNING: ", initialClampCount, " initial layer frequency/frequencies were constrained by the safe synthesis range."
endif

# === Apply Fade ===
appendInfoLine: "Applying envelope..."
if fade_time_s > 0
    selectObject: outputSound
    fadeInStr$ = string$(fade_time_s)
    fadeOutStart = duration_s - fade_time_s
    fadeOutStartStr$ = string$(fadeOutStart)
    durationStr$ = string$(duration_s)

    Formula: "if x < " + fadeInStr$ + " then self * (x / " + fadeInStr$ + ") else self fi"
    Formula: "if x > " + fadeOutStartStr$ + " then self * ((" + durationStr$ + " - x) / " + fadeInStr$ + ") else self fi"
endif

# === Spatial Processing ===
if spatial_mode = 2
    appendInfoLine: "Creating stereo width..."

    # Nyquist-safe complementary-ish spectral widening.
    leftHigh = min(4000, 0.42 * sample_rate_Hz)
    rightHigh = min(8000, 0.45 * sample_rate_Hz)
    rightLow = min(200, 0.20 * rightHigh)
    filterSmooth = min(100, max(20, 0.05 * leftHigh))

    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * 0.8"
    Filter (pass Hann band): 0, leftHigh, filterSmooth
    leftFiltered = selected("Sound")
    removeObject: leftSound
    leftSound = leftFiltered

    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * 0.8"
    Filter (pass Hann band): rightLow, rightHigh, filterSmooth
    rightFiltered = selected("Sound")
    removeObject: rightSound
    rightSound = rightFiltered

    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "brownian_" + preset_name$

    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound

elsif spatial_mode = 3
    appendInfoLine: "Creating equal-power rotating stereo..."

    # A single pan trajectory is mapped to complementary equal-power gains.
    # pan = -1 -> left, +1 -> right.
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * sqrt(max(0, (1 - sin(twoPi * 0.15 * x)) / 2))"

    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * sqrt(max(0, (1 + sin(twoPi * 0.15 * x)) / 2))"

    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "brownian_" + preset_name$

    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound

else
    selectObject: outputSound
    Rename: "brownian_" + preset_name$
endif

# === Normalize ===
if normalize_output
    selectObject: outputSound
    Scale peak: 0.9
endif

# === Visualization ===
if draw_visualization
    appendInfoLine: "Drawing Brownian-process figure..."
    @drawBrownianFigure: duration_s
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
appendInfoLine: "Created: ", selected$("Sound")

# ==============================================================================
# Procedure: drawBrownianFigure
# ==============================================================================
procedure drawBrownianFigure: .duration

    # ------------------------------------------------------------
    # Layout / palette
    # ------------------------------------------------------------
    .leftViewport = 0.78
    .rightViewport = 7.58

    .pathCol1$ = "{0.20, 0.45, 0.70}"
    .pathCol2$ = "{0.70, 0.38, 0.28}"
    .pathCol3$ = "{0.35, 0.58, 0.38}"
    .gridCol$ = "{0.72, 0.72, 0.72}"
    .bg$ = "{0.975, 0.975, 0.978}"

    if .duration <= 4
        .tTick = 0.5
    elsif .duration <= 10
        .tTick = 1
    elsif .duration <= 20
        .tTick = 2
    else
        .tTick = 5
    endif

    if spatial_mode = 2
        .spatial$ = "Stereo Wide"
    elsif spatial_mode = 3
        .spatial$ = "Rotating"
    else
        .spatial$ = "Mono"
    endif

    Erase all

    # ------------------------------------------------------------
    # Main title
    # ------------------------------------------------------------
    Select inner viewport: 0.2, 7.8, 0.06, 0.34
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.55, "half", "Advanced Brownian Synthesis | " + preset_name$

    # Metadata / model strip
    Select inner viewport: 0.35, 7.65, 0.38, 0.68
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.35, 0.35, 0.35}"
    if enable_drift
        Text: 0.5, "centre", 0.68, "half", synthesis_mode$ + " | " + string$(number_of_layers) + " layers | " + seedLabel$ + " | " + .spatial$
        Text: 0.5, "centre", 0.22, "half", "Brownian/OU rule: df = k(mu-f)dt + sigma sqrt(dt) N(0,1)"
    else
        Text: 0.5, "centre", 0.68, "half", synthesis_mode$ + " | " + string$(number_of_layers) + " layers | " + seedLabel$ + " | " + .spatial$
        Text: 0.5, "centre", 0.22, "half", "Brownian rule: df = sigma sqrt(dt) N(0,1)   (mean reversion disabled)"
    endif

    # ------------------------------------------------------------
    # PANEL A TITLE
    # ------------------------------------------------------------
    Select inner viewport: 0.35, 7.65, 0.76, 0.98
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.52, "half", "A  ACTUAL FREQUENCY TRAJECTORIES | solid = realized path, dotted = target"

    # PANEL A DATA
    .freqRange = globalMaxFreq - globalMinFreq
    if .freqRange < 20
        .freqRange = 20
    endif
    .freqPad = max(10, 0.08 * .freqRange)
    .yMin = max(0, globalMinFreq - .freqPad)
    .yMax = min(highFreq * 1.02, globalMaxFreq + .freqPad)
    if .yMax <= .yMin
        .yMax = .yMin + 20
    endif

    Select inner viewport: .leftViewport, .rightViewport, 1.04, 2.28
    Axes: 0, .duration, .yMin, .yMax
    Paint rectangle: .bg$, 0, .duration, .yMin, .yMax

    # Target frequencies.
    Colour: .gridCol$
    Dotted line
    for .layer to number_of_layers
        .target = vizTarget[.layer]
        if .target >= .yMin and .target <= .yMax
            Draw line: 0, .target, .duration, .target
        endif
    endfor
    Plain line

    # Real trajectories.
    Line width: 1.2
    for .layer to number_of_layers
        if (.layer mod 3) = 1
            Colour: .pathCol1$
        elsif (.layer mod 3) = 2
            Colour: .pathCol2$
        else
            Colour: .pathCol3$
        endif

        .count = vizCount[.layer]
        if .count > 1
            for .j from 2 to .count
                .idx1 = (.layer - 1) * maxVizPerLayer + .j - 1
                .idx2 = (.layer - 1) * maxVizPerLayer + .j
                Draw line: vizTime[.idx1], vizFreq[.idx1], vizTime[.idx2], vizFreq[.idx2]
            endfor
        endif
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Marks left: 5, "yes", "yes", "no"
    Marks bottom every: 1, .tTick, "no", "yes", "yes"
    Font size: 6
    Text left: "yes", "Frequency (Hz)"

    # ------------------------------------------------------------
    # PANEL B TITLE
    # ------------------------------------------------------------
    Select inner viewport: 0.35, 7.65, 2.40, 2.62
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.52, "half", "B  OUTPUT WAVEFORM | representative channel"

    # Representative mono display copy: use channel 1 rather than a fold-down
    # so stereo phase relationships cannot cancel in the visualization.
    if spatial_mode > 1
        selectObject: outputSound
        Extract one channel: 1
        .disp = selected("Sound")
        .waveLabel$ = "Output ch1"
    else
        selectObject: outputSound
        Copy: "disp_" + uid$
        .disp = selected("Sound")
        .waveLabel$ = "Output"
    endif

    selectObject: .disp
    .peak = Get absolute extremum: 0, 0, "None"
    if .peak = undefined or .peak <= 0
        .peak = 1
    endif
    .waveLim = 1.06 * .peak

    Select inner viewport: .leftViewport, .rightViewport, 2.68, 3.70
    Axes: 0, .duration, -.waveLim, .waveLim
    Paint rectangle: .bg$, 0, .duration, -.waveLim, .waveLim
    Colour: "{0.20, 0.45, 0.65}"
    selectObject: .disp
    Draw: 0, .duration, -.waveLim, .waveLim, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, .tTick, "no", "yes", "yes"
    Font size: 6
    Text left: "yes", .waveLabel$

    # ------------------------------------------------------------
    # PANEL C TITLE
    # ------------------------------------------------------------
    Select inner viewport: 0.35, 7.65, 3.84, 4.06
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.52, "half", "C  MEASURED SPECTROGRAM + MODEL PATHS | overlay = actual Brownian trajectories"

    # PANEL C DATA
    .maxFreqSpec = min(0.48 * sample_rate_Hz, max(1000, 1.15 * globalMaxFreq))
    .maxFreqSpec = min(.maxFreqSpec, 9000)

    Select inner viewport: .leftViewport, .rightViewport, 4.12, 6.22
    selectObject: .disp
    To Spectrogram: 0.03, .maxFreqSpec, 0.005, 20, "Gaussian"
    .spec = selected("Spectrogram")
    Paint: 0, .duration, 0, .maxFreqSpec, 100, "yes", 50, 6, 0, "no"
    removeObject: .spec

    # IMPORTANT: Paint/Text/box state can leave another viewport active.
    # Re-select the data viewport and reset world coordinates before overlay.
    Select inner viewport: .leftViewport, .rightViewport, 4.12, 6.22
    Axes: 0, .duration, 0, .maxFreqSpec

    Line width: 1.2
    for .layer to number_of_layers
        if (.layer mod 3) = 1
            Colour: .pathCol1$
        elsif (.layer mod 3) = 2
            Colour: .pathCol2$
        else
            Colour: .pathCol3$
        endif

        .count = vizCount[.layer]
        if .count > 1
            for .j from 2 to .count
                .idx1 = (.layer - 1) * maxVizPerLayer + .j - 1
                .idx2 = (.layer - 1) * maxVizPerLayer + .j
                if vizFreq[.idx1] <= .maxFreqSpec and vizFreq[.idx2] <= .maxFreqSpec
                    Draw line: vizTime[.idx1], vizFreq[.idx1], vizTime[.idx2], vizFreq[.idx2]
                endif
            endfor
        endif
    endfor

    Line width: 1
    Colour: "Black"
    Draw inner box
    Marks left: 5, "yes", "yes", "no"
    Marks bottom every: 1, .tTick, "yes", "yes", "no"
    Font size: 6
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Frequency (Hz)"

    removeObject: .disp

    # ------------------------------------------------------------
    # SUMMARY BAR
    # ------------------------------------------------------------
    Select inner viewport: 0.35, 7.65, 6.42, 7.16
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1

    Font size: 5
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.5, "centre", 0.70, "half", "Base " + fixed$(base_frequency_Hz, 0) + " Hz | Spread " + fixed$(frequency_spread_Hz, 1) + " Hz | Step " + fixed$(step_size, 1) + " Hz/frame | Drift " + fixed$(drift_force, 2) + " /s | " + .spatial$
    Text: 0.5, "centre", 0.30, "half", "Realized " + fixed$(globalMinFreq, 1) + "-" + fixed$(globalMaxFreq, 1) + " Hz | RMS step " + fixed$(realizedStepRms, 2) + " Hz | Reflections " + string$(boundaryReflections) + " | " + seedLabel$

    Font size: 10
    Colour: "Black"
    Line width: 1
endproc
