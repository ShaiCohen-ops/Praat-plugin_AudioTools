# ============================================================
# Praat AudioTools - Advanced Formula Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 reviewed (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Formula-based synthesis with six bounded synthesis families:
#   - Simple FM
#   - Competing Oscillators (phi, e ratios)
#   - Nested FM / phase modulation
#   - Harmonic Series
#   - Fibonacci Series
#   - Evolutionary Formula
#
# Usage:
#   Run this script (no input Sound required).
#
# Changelog v0.4 reviewed:
#   - Replaced time-multiplied frequency warping of the form
#       sin(2*pi*f*t*(1+m(t)))
#     with bounded FM / phase-modulation equations. The old form creates an
#     extra t*m'(t) term in instantaneous frequency, so modulation depth grows
#     with elapsed time and can become extreme late in a sound.
#   - Modulation_depth now actually affects Competing Oscillators.
#   - Renamed Fibonacci Ratios to Fibonacci Series: the generated carriers are
#     Fibonacci multiples (1, 2, 3, 5, 8, 13...), not ratios converging to phi.
#   - Added Random_seed (0 = unpredictable, positive = reproducible) and restore
#     of Praat's RNG state after synthesis.
#   - Replaced dynamic name-based Sound access with unique object-ID access.
#   - Added Nyquist-aware component guards and modulation-depth reduction.
#   - Made evolutionary decay strictly non-negative.
#   - Made Rotating stereo complementary equal-power.
#   - Made Stereo Wide filter limits sample-rate aware.
#   - Rebuilt visualization around the actual synthesis claim: measured output,
#     measured spectrogram, actual realized layer parameters, governing formula,
#     process chain, and compact QC summary.
# ============================================================

form Advanced Formula Synthesis
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Gentle Waves
        option Golden Ratio Drone
        option Nested Complexity
        option Pure Harmonics
        option Fibonacci Bells
        option Slow Evolution
        option Dense Texture

    comment === Basic Settings ===
    positive Duration_s 8.0
    integer Sample_rate_Hz 44100
    positive Base_frequency_Hz 100
    integer Number_of_layers 4

    comment === Modulation ===
    real Modulation_depth 0.6
    real Complexity_factor 1.0
    real Evolution_speed 1.0
    boolean Randomize_parameters 1
    integer Random_seed 0

    comment === Synthesis Mode ===
    optionmenu Synthesis_mode 1
        option Simple FM
        option Competing Oscillators
        option Nested FM
        option Harmonic Series
        option Fibonacci Series
        option Evolutionary Formula

    comment === Output ===
    positive Fade_time_s 2
    optionmenu Spatial_mode 1
        option Mono
        option Stereo Wide
        option Rotating
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# -----------------------------------------------------------------------------
# 1. Presets
# -----------------------------------------------------------------------------
preset_name$ = "Custom"

if preset = 2
    duration_s = 10
    base_frequency_Hz = 150
    number_of_layers = 3
    modulation_depth = 0.3
    complexity_factor = 0.5
    synthesis_mode = 1
    spatial_mode = 1
    synthesis_mode$ = "Simple FM"
    preset_name$ = "GentleWaves"
elsif preset = 3
    duration_s = 15
    base_frequency_Hz = 80
    number_of_layers = 4
    modulation_depth = 0.4
    complexity_factor = 1.0
    synthesis_mode = 2
    spatial_mode = 3
    synthesis_mode$ = "Competing Oscillators"
    preset_name$ = "GoldenRatioDrone"
elsif preset = 4
    duration_s = 12
    base_frequency_Hz = 120
    number_of_layers = 5
    modulation_depth = 0.7
    complexity_factor = 1.5
    synthesis_mode = 3
    spatial_mode = 2
    synthesis_mode$ = "Nested FM"
    preset_name$ = "NestedComplexity"
elsif preset = 5
    duration_s = 8
    base_frequency_Hz = 110
    number_of_layers = 6
    modulation_depth = 0.2
    complexity_factor = 0.8
    synthesis_mode = 4
    spatial_mode = 1
    synthesis_mode$ = "Harmonic Series"
    preset_name$ = "PureHarmonics"
elsif preset = 6
    duration_s = 10
    base_frequency_Hz = 220
    number_of_layers = 6
    modulation_depth = 0.3
    complexity_factor = 1.0
    synthesis_mode = 5
    spatial_mode = 2
    fade_time_s = 3
    synthesis_mode$ = "Fibonacci Series"
    preset_name$ = "FibonacciBells"
elsif preset = 7
    duration_s = 20
    base_frequency_Hz = 60
    number_of_layers = 3
    modulation_depth = 0.5
    evolution_speed = 0.3
    synthesis_mode = 6
    spatial_mode = 3
    fade_time_s = 4
    synthesis_mode$ = "Evolutionary Formula"
    preset_name$ = "SlowEvolution"
elsif preset = 8
    duration_s = 8
    base_frequency_Hz = 200
    number_of_layers = 8
    modulation_depth = 0.8
    complexity_factor = 2.0
    evolution_speed = 1.5
    synthesis_mode = 6
    spatial_mode = 2
    synthesis_mode$ = "Evolutionary Formula"
    preset_name$ = "DenseTexture"
endif

# -----------------------------------------------------------------------------
# 2. Validation / safe operating range
# -----------------------------------------------------------------------------
if number_of_layers > 8
    number_of_layers = 8
endif
if number_of_layers < 1
    number_of_layers = 1
endif
if sample_rate_Hz < 4000
    sample_rate_Hz = 4000
endif
if sample_rate_Hz > 192000
    sample_rate_Hz = 192000
endif
if fade_time_s > duration_s / 2
    fade_time_s = duration_s / 2
endif
if modulation_depth < 0
    modulation_depth = 0
endif
if modulation_depth > 1
    modulation_depth = 1
endif
if complexity_factor < 0
    complexity_factor = 0
endif
if complexity_factor > 5
    complexity_factor = 5
endif
if evolution_speed < 0.01
    evolution_speed = 0.01
endif
if evolution_speed > 20
    evolution_speed = 20
endif
if random_seed < 0
    random_seed = 0
endif

# -----------------------------------------------------------------------------
# 3. Constants and reproducibility
# -----------------------------------------------------------------------------
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi
phi = (1 + sqrt(5)) / 2
euler = exp(1)
nyquist = sample_rate_Hz / 2
nyquistSafe = 0.90 * nyquist
antiAliasReductions = 0
skippedComponents = 0
maxModelFreq = base_frequency_Hz

if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
endif

# Fibonacci successive ratios. Their cumulative product gives the Fibonacci
# multiples 1, 2, 3, 5, 8, 13, 21, 34 for layers 1..8.
fib1 = 1
fib2 = 1
fibRatio_1 = 1
for f from 2 to 8
    fibNew = fib1 + fib2
    fib1 = fib2
    fib2 = fibNew
    fibRatio_'f' = fib2 / fib1
endfor

writeInfoLine: "=== Advanced Formula Synthesis ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", duration_s, " s"
appendInfoLine: "Layers: ", number_of_layers
appendInfoLine: "Mode: ", synthesis_mode$
if randomize_parameters
    if random_seed > 0
        appendInfoLine: "Randomization: reproducible seed ", random_seed
    else
        appendInfoLine: "Randomization: unpredictable"
    endif
else
    appendInfoLine: "Randomization: off"
endif
appendInfoLine: ""

# -----------------------------------------------------------------------------
# 4. Output accumulator
# -----------------------------------------------------------------------------
outputSound = Create Sound from formula: "formula_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"

# -----------------------------------------------------------------------------
# 5. Synthesis
# -----------------------------------------------------------------------------
for layer to number_of_layers
    appendInfoLine: "Layer ", layer, "/", number_of_layers, "..."

    if randomize_parameters
        baseFreq = base_frequency_Hz * (0.8 + 0.4 * randomUniform(0, 1))
        modDepth = modulation_depth * (0.7 + 0.6 * randomUniform(0, 1))
        if modDepth > 1
            modDepth = 1
        endif
        evoSpeed = evolution_speed * (0.5 + randomUniform(0, 1))
        phaseOffset = randomUniform(0, twoPi)
    else
        baseFreq = base_frequency_Hz
        modDepth = modulation_depth
        evoSpeed = evolution_speed
        phaseOffset = 0
    endif

    realizedBase_'layer' = baseFreq
    realizedMod_'layer' = modDepth
    realizedEvo_'layer' = evoSpeed

    # -------------------------------------------------------------------------
    # Mode 1: Simple FM
    # f(t) = fc * [1 + d cos(2*pi*fm*t)]
    # phase(t) = 2*pi*fc*t + beta*sin(2*pi*fm*t), beta = fc*d/fm
    # -------------------------------------------------------------------------
    if synthesis_mode = 1
        layerAmp = 0.6 / number_of_layers
        fmRate = 2
        relDepth = 0.30 * modDepth
        layerGain = 1

        if baseFreq >= nyquistSafe
            layerGain = 0
            skippedComponents = skippedComponents + 1
            relDepth = 0
        else
            availableRel = nyquistSafe / baseFreq - 1
            if relDepth > availableRel
                relDepth = max(0, availableRel)
                antiAliasReductions = antiAliasReductions + 1
            endif
        endif

        beta = baseFreq * relDepth / fmRate
        modelTop = baseFreq * (1 + relDepth)
        if modelTop > maxModelFreq
            maxModelFreq = modelTop
        endif
        primaryFreq_'layer' = baseFreq
        primaryTop_'layer' = modelTop

        layerSound = Create Sound from formula: "layer_" + uid$, 1, 0, duration_s, sample_rate_Hz,
            ... "layerGain * layerAmp * sin(twoPi * baseFreq * x + beta * sin(twoPi * fmRate * x) + phaseOffset) * (0.7 + 0.3 * sin(twoPi * 0.1 * x))"

    # -------------------------------------------------------------------------
    # Mode 2: Competing Oscillators. Three incommensurate carriers with
    # independently bounded FM. Modulation_depth now scales all three.
    # -------------------------------------------------------------------------
    elsif synthesis_mode = 2
        layerAmp = 0.5 / number_of_layers
        fc1 = baseFreq
        fc2 = baseFreq * phi
        fc3 = baseFreq * euler
        fm1 = 1.5
        fm2 = 2.5
        fm3 = 0.7
        rel1 = 0.20 * modDepth
        rel2 = 0.30 * modDepth
        rel3 = 0.40 * modDepth
        g1 = 1
        g2 = 1
        g3 = 1

        if fc1 >= nyquistSafe
            g1 = 0
            rel1 = 0
            skippedComponents = skippedComponents + 1
        else
            avail1 = nyquistSafe / fc1 - 1
            if rel1 > avail1
                rel1 = max(0, avail1)
                antiAliasReductions = antiAliasReductions + 1
            endif
        endif
        if fc2 >= nyquistSafe
            g2 = 0
            rel2 = 0
            skippedComponents = skippedComponents + 1
        else
            avail2 = nyquistSafe / fc2 - 1
            if rel2 > avail2
                rel2 = max(0, avail2)
                antiAliasReductions = antiAliasReductions + 1
            endif
        endif
        if fc3 >= nyquistSafe
            g3 = 0
            rel3 = 0
            skippedComponents = skippedComponents + 1
        else
            avail3 = nyquistSafe / fc3 - 1
            if rel3 > avail3
                rel3 = max(0, avail3)
                antiAliasReductions = antiAliasReductions + 1
            endif
        endif

        beta1 = fc1 * rel1 / fm1
        beta2 = fc2 * rel2 / fm2
        beta3 = fc3 * rel3 / fm3
        modelTop = max(fc1 * (1 + rel1), fc2 * (1 + rel2), fc3 * (1 + rel3))
        if modelTop > maxModelFreq
            maxModelFreq = modelTop
        endif
        primaryFreq_'layer' = fc1
        primaryTop_'layer' = fc1 * (1 + rel1)

        layerSound = Create Sound from formula: "layer_" + uid$, 1, 0, duration_s, sample_rate_Hz,
            ... "layerAmp * (g1 * sin(twoPi * fc1 * x + beta1 * sin(twoPi * fm1 * x) + phaseOffset) + 0.5 * g2 * sin(twoPi * fc2 * x + beta2 * sin(twoPi * fm2 * x) + 0.37 + phaseOffset) + 0.3 * g3 * sin(twoPi * fc3 * x + beta3 * sin(twoPi * fm3 * x) + 0.73 + phaseOffset)) * (0.6 + 0.4 * sin(twoPi * 0.05 * x))"

    # -------------------------------------------------------------------------
    # Mode 3: Nested FM / bounded phase modulation.
    # Unlike the old x*(1+m(t)) expression, nesting occurs inside phase and
    # therefore does not grow with elapsed time.
    # -------------------------------------------------------------------------
    elsif synthesis_mode = 3
        layerAmp = 0.55 / number_of_layers
        complexity = complexity_factor
        rateScale = max(0.05, complexity)
        fc1 = baseFreq
        fc2 = 1.5 * baseFreq
        fc3 = 2.2 * baseFreq
        g1 = 1
        g2 = 1
        g3 = 1
        if fc1 >= nyquistSafe
            g1 = 0
            skippedComponents = skippedComponents + 1
        endif
        if fc2 >= nyquistSafe
            g2 = 0
            skippedComponents = skippedComponents + 1
        endif
        if fc3 >= nyquistSafe
            g3 = 0
            skippedComponents = skippedComponents + 1
        endif

        betaOuter1 = 2.5 * modDepth
        betaOuter2 = 2.0 * modDepth
        betaOuter3 = 3.0 * modDepth
        betaInner1 = min(2.5, 0.5 + 0.7 * complexity)
        betaInner2 = min(2.5, 0.4 + 0.5 * complexity)
        betaInner3 = min(2.5, 0.6 + 0.6 * complexity)
        modelTop = max(fc1, fc2, fc3)
        if modelTop > maxModelFreq
            maxModelFreq = modelTop
        endif
        primaryFreq_'layer' = fc1
        primaryTop_'layer' = fc1

        layerSound = Create Sound from formula: "layer_" + uid$, 1, 0, duration_s, sample_rate_Hz,
            ... "layerAmp * (g1 * sin(twoPi * fc1 * x + betaOuter1 * sin(twoPi * 1.2 * rateScale * x + betaInner1 * sin(twoPi * 0.3 * rateScale * x)) + phaseOffset) + 0.7 * g2 * sin(twoPi * fc2 * x + betaOuter2 * sin(twoPi * 2.1 * rateScale * x + betaInner2 * sin(twoPi * 0.5 * rateScale * x)) + 0.41 + phaseOffset) + 0.4 * g3 * sin(twoPi * fc3 * x + betaOuter3 * sin(twoPi * 0.9 * rateScale * x + betaInner3 * sin(twoPi * 0.2 * rateScale * x)) + 0.83 + phaseOffset)) * (0.5 + 0.5 * sin(twoPi * 0.08 * x)) * exp(-0.3 * x / duration_s)"

    # -------------------------------------------------------------------------
    # Mode 4: Harmonic Series. Harmonic relations remain exact; randomization
    # affects starting phase only, not the harmonic frequencies.
    # -------------------------------------------------------------------------
    elsif synthesis_mode = 4
        harmonic = layer
        layerFreq = base_frequency_Hz * harmonic
        layerAmp = 0.7 / (number_of_layers * harmonic)
        complexity = complexity_factor
        layerGain = 1
        if layerFreq >= nyquistSafe
            layerGain = 0
            skippedComponents = skippedComponents + 1
        endif
        if layerFreq > maxModelFreq and layerGain > 0
            maxModelFreq = layerFreq
        endif
        primaryFreq_'layer' = layerFreq
        primaryTop_'layer' = layerFreq

        layerSound = Create Sound from formula: "layer_" + uid$, 1, 0, duration_s, sample_rate_Hz,
            ... "layerGain * layerAmp * sin(twoPi * layerFreq * x + phaseOffset) * (0.8 + 0.2 * sin(twoPi * complexity * 0.15 * x)) * (1 - 0.3 * sin(twoPi * complexity * 0.08 * x))"

    # -------------------------------------------------------------------------
    # Mode 5: Fibonacci Series. Carrier multiples are 1,2,3,5,8,13,...
    # -------------------------------------------------------------------------
    elsif synthesis_mode = 5
        fibCum = 1
        for f from 2 to layer
            fibCum = fibCum * fibRatio_'f'
        endfor

        layerFreq = base_frequency_Hz * fibCum
        layerAmp = 0.65 / (number_of_layers * sqrt(fibCum))
        if randomize_parameters
            modRate = 0.5 + randomUniform(0, 1.5)
        else
            modRate = 1.0
        endif
        relDepth = 0.20 * modDepth
        layerGain = 1
        if layerFreq >= nyquistSafe
            layerGain = 0
            relDepth = 0
            skippedComponents = skippedComponents + 1
        else
            availableRel = nyquistSafe / layerFreq - 1
            if relDepth > availableRel
                relDepth = max(0, availableRel)
                antiAliasReductions = antiAliasReductions + 1
            endif
        endif
        beta = layerFreq * relDepth / modRate
        modelTop = layerFreq * (1 + relDepth)
        if modelTop > maxModelFreq and layerGain > 0
            maxModelFreq = modelTop
        endif
        primaryFreq_'layer' = layerFreq
        primaryTop_'layer' = modelTop

        layerSound = Create Sound from formula: "layer_" + uid$, 1, 0, duration_s, sample_rate_Hz,
            ... "layerGain * layerAmp * sin(twoPi * layerFreq * x + beta * sin(twoPi * modRate * x) + phaseOffset) * (0.6 + 0.4 * sin(twoPi * complexity_factor * 0.1 * x))"

    # -------------------------------------------------------------------------
    # Mode 6: Evolutionary Formula. Four related carriers receive bounded,
    # multi-rate FM plus slow amplitude evolution. The global decay is positive.
    # -------------------------------------------------------------------------
    else
        layerAmp = 0.8 / number_of_layers
        complexity = complexity_factor
        rateScale = evoSpeed * (0.6 + 0.4 * max(0.1, complexity))
        fc1 = baseFreq
        fc2 = baseFreq * (4/3)
        fc3 = baseFreq * (5/3)
        fc4 = baseFreq * 2
        g1 = 1
        g2 = 1
        g3 = 1
        g4 = 1
        if fc1 >= nyquistSafe
            g1 = 0
            skippedComponents = skippedComponents + 1
        endif
        if fc2 >= nyquistSafe
            g2 = 0
            skippedComponents = skippedComponents + 1
        endif
        if fc3 >= nyquistSafe
            g3 = 0
            skippedComponents = skippedComponents + 1
        endif
        if fc4 >= nyquistSafe
            g4 = 0
            skippedComponents = skippedComponents + 1
        endif

        fm1a = max(0.02, 0.3 * rateScale)
        fm1b = max(0.02, 2.0 * rateScale)
        fm2 = max(0.02, 0.5 * rateScale)
        fm3 = max(0.02, 0.8 * rateScale)
        fm4 = max(0.02, 1.1 * rateScale)
        r1a = 0.25 * modDepth
        r1b = 0.15 * modDepth
        r2 = 0.30 * modDepth
        r3 = 0.40 * modDepth
        r4 = 0.45 * modDepth

        if g1 > 0
            avail1 = nyquistSafe / fc1 - 1
            if r1a + r1b > avail1
                scale1 = max(0, avail1) / max(1e-12, r1a + r1b)
                r1a = r1a * scale1
                r1b = r1b * scale1
                antiAliasReductions = antiAliasReductions + 1
            endif
        endif
        if g2 > 0
            avail2 = nyquistSafe / fc2 - 1
            if r2 > avail2
                r2 = max(0, avail2)
                antiAliasReductions = antiAliasReductions + 1
            endif
        endif
        if g3 > 0
            avail3 = nyquistSafe / fc3 - 1
            if r3 > avail3
                r3 = max(0, avail3)
                antiAliasReductions = antiAliasReductions + 1
            endif
        endif
        if g4 > 0
            avail4 = nyquistSafe / fc4 - 1
            if r4 > avail4
                r4 = max(0, avail4)
                antiAliasReductions = antiAliasReductions + 1
            endif
        endif

        b1a = fc1 * r1a / fm1a
        b1b = fc1 * r1b / fm1b
        b2 = fc2 * r2 / fm2
        b3 = fc3 * r3 / fm3
        b4 = fc4 * r4 / fm4
        modelTop = max(fc1 * (1 + r1a + r1b), fc2 * (1 + r2), fc3 * (1 + r3), fc4 * (1 + r4))
        if modelTop > maxModelFreq
            maxModelFreq = modelTop
        endif
        primaryFreq_'layer' = fc1
        primaryTop_'layer' = fc1 * (1 + r1a + r1b)
        decayRate = 0.15 * complexity

        layerSound = Create Sound from formula: "layer_" + uid$, 1, 0, duration_s, sample_rate_Hz,
            ... "layerAmp * (g1 * sin(twoPi * fc1 * x + b1a * sin(twoPi * fm1a * x) + b1b * sin(twoPi * fm1b * x) + phaseOffset) * (0.7 + 0.3 * sin(twoPi * 0.1 * evoSpeed * x)) + 0.8 * g2 * sin(twoPi * fc2 * x + b2 * sin(twoPi * fm2 * x) + 0.33 + phaseOffset) * (0.6 + 0.4 * sin(twoPi * 0.07 * evoSpeed * x)) + 0.6 * g3 * sin(twoPi * fc3 * x + b3 * sin(twoPi * fm3 * x) + 0.67 + phaseOffset) * (0.5 + 0.5 * sin(twoPi * 0.12 * evoSpeed * x)) + 0.4 * g4 * sin(twoPi * fc4 * x + b4 * sin(twoPi * fm4 * x) + 1.01 + phaseOffset) * (0.4 + 0.6 * sin(twoPi * 0.15 * evoSpeed * x))) * (0.8 + 0.2 * sin(twoPi * 0.02 * evoSpeed * x)) * exp(-decayRate * x / duration_s)"
    endif

    # Add this layer by object ID. Time-based access is unambiguous and returns
    # the corresponding sample from the generated mono layer.
    selectObject: outputSound
    Formula: "self + object(layerSound, x, 1)"
    removeObject: layerSound
endfor

# Restore unpredictable RNG state after all randomized synthesis choices.
if random_seed > 0
    random_initializeSafelyAndUnpredictably ()
endif

# -----------------------------------------------------------------------------
# 6. Fade
# -----------------------------------------------------------------------------
appendInfoLine: "Applying envelope..."
selectObject: outputSound
Formula: "if x < fade_time_s then self * (x / fade_time_s) else self fi"
fadeOutStart = duration_s - fade_time_s
Formula: "if x > fadeOutStart then self * ((duration_s - x) / fade_time_s) else self fi"

# -----------------------------------------------------------------------------
# 7. Spatial processing
# -----------------------------------------------------------------------------
if spatial_mode = 2
    appendInfoLine: "Creating stereo width..."
    filterTop = min(8000, 0.90 * nyquist)
    leftTop = min(4000, filterTop)
    rightLow = min(200, 0.20 * filterTop)
    transition = min(100, 0.05 * nyquist)
    if transition < 20
        transition = 20
    endif

    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * 0.8"
    Filter (pass Hann band): 0, leftTop, transition
    leftFiltered = selected("Sound")
    removeObject: leftSound
    leftSound = leftFiltered

    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * 0.8"
    Filter (pass Hann band): rightLow, filterTop, transition
    rightFiltered = selected("Sound")
    removeObject: rightSound
    rightSound = rightFiltered

    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "formula_" + preset_name$

    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound

elsif spatial_mode = 3
    appendInfoLine: "Creating equal-power rotating stereo..."

    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * sqrt(0.5 * (1 + cos(twoPi * 0.2 * x)))"

    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * sqrt(0.5 * (1 - cos(twoPi * 0.2 * x)))"

    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "formula_" + preset_name$

    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound
else
    selectObject: outputSound
    Rename: "formula_" + preset_name$
endif

# -----------------------------------------------------------------------------
# 8. Output level
# -----------------------------------------------------------------------------
if normalize_output
    selectObject: outputSound
    Scale peak: 0.9
endif

selectObject: outputSound
finalPeak = Get absolute extremum: 0, 0, "Sinc70"
finalRms = Get root-mean-square: 0, 0

# Build a concise actual-realization string for the mechanism panel.
realizedList$ = "Primary carriers:"
for layer to number_of_layers
    realizedList$ = realizedList$ + " " + fixed$(primaryFreq_'layer', 1)
endfor
realizedList$ = realizedList$ + " Hz"

# -----------------------------------------------------------------------------
# 9. Visualization
# -----------------------------------------------------------------------------
if draw_visualization
    appendInfoLine: "Drawing visualization..."
    @drawSynthesisQC: duration_s
endif

if play_result
    selectObject: outputSound
    Play
endif

selectObject: outputSound
appendInfoLine: ""
appendInfoLine: "Anti-alias depth reductions: ", antiAliasReductions
appendInfoLine: "Skipped out-of-band components: ", skippedComponents
appendInfoLine: "Final peak: ", fixed$(finalPeak, 4)
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# ==============================================================================
# Procedure: drawSynthesisQC
# ==============================================================================
procedure drawSynthesisQC: .duration
    # AudioTools research layout: title strips are independent from data panels;
    # axes are explicitly reset after text/box drawing; each panel has one job.

    .bg$ = "{0.975, 0.975, 0.978}"
    .blue$ = "{0.16, 0.40, 0.68}"
    .rust$ = "{0.66, 0.33, 0.20}"
    .grey$ = "{0.38, 0.38, 0.42}"

    if .duration <= 2
        .tTick = 0.2
    elsif .duration <= 5
        .tTick = 0.5
    elsif .duration <= 12
        .tTick = 1
    elsif .duration <= 25
        .tTick = 2
    else
        .tTick = 5
    endif

    Erase all
    Select outer viewport: 0, 8, 0, 8
    Black
    Plain line
    Line width: 1

    # --- Header ---
    Select inner viewport: 0.35, 7.65, 0.08, 0.48
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.63, "half", "##Advanced Formula Synthesis##"

    Select inner viewport: 0.35, 7.65, 0.50, 0.84
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: .grey$
    Text: 0.5, "centre", 0.55, "half", preset_name$ + "   |   " + synthesis_mode$ + "   |   " + fixed$(sample_rate_Hz / 1000, 1) + " kHz   |   " + string$(number_of_layers) + " layers"

    # --- Strong / representative display channel ---
    selectObject: outputSound
    .nchan = Get number of channels
    if .nchan = 1
        Copy: "afs_disp_" + uid$
        .disp = selected("Sound")
        .channelLabel$ = "mono"
    else
        Extract one channel: 1
        .left = selected("Sound")
        .rmsLeft = Get root-mean-square: 0, 0
        selectObject: outputSound
        Extract one channel: 2
        .right = selected("Sound")
        .rmsRight = Get root-mean-square: 0, 0
        if .rmsLeft >= .rmsRight
            removeObject: .right
            .disp = .left
            .channelLabel$ = "L"
        else
            removeObject: .left
            .disp = .right
            .channelLabel$ = "R"
        endif
    endif

    selectObject: .disp
    .peak = Get absolute extremum: 0, 0, "Sinc70"
    if .peak <= 0
        .peak = 1
    endif
    .waveY = 1.08 * .peak

    # --- Panel A title ---
    Select inner viewport: 0.65, 7.55, 1.00, 1.25
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0, "left", 0.52, "half", "##A  Measured output waveform##   |   representative channel " + .channelLabel$

    # --- Panel A data ---
    Select inner viewport: 0.75, 7.55, 1.32, 2.58
    selectObject: .disp
    Colour: .blue$
    Draw: 0, .duration, -.waveY, .waveY, "no", "Curve"
    Select inner viewport: 0.75, 7.55, 1.32, 2.58
    Axes: 0, .duration, -.waveY, .waveY
    Colour: "Black"
    Draw inner box
    Font size: 7
    Marks left: 3, "yes", "yes", "no"
    Marks bottom every: 1, .tTick, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Amplitude"

    # --- Panel B title ---
    Select inner viewport: 0.65, 7.55, 2.82, 3.07
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0, "left", 0.52, "half", "##B  Measured spectrogram##   |   consequence of the formula field"

    # --- Panel B data ---
    .maxFreqSpec = min(nyquistSafe, max(2000, 1.35 * maxModelFreq))
    selectObject: .disp
    To Spectrogram: 0.03, .maxFreqSpec, 0.005, 20, "Gaussian"
    .spec = selected("Spectrogram")
    Select inner viewport: 0.75, 7.55, 3.14, 5.05
    Paint: 0, .duration, 0, .maxFreqSpec, 100, "yes", 50, 6, 0, "no"
    removeObject: .spec

    Select inner viewport: 0.75, 7.55, 3.14, 5.05
    Axes: 0, .duration, 0, .maxFreqSpec
    Colour: "Black"
    Draw inner box
    Font size: 7
    Marks left: 5, "yes", "yes", "no"
    Marks bottom every: 1, .tTick, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Frequency (Hz)"

    # --- Panel C title ---
    Select inner viewport: 0.65, 7.55, 5.28, 5.53
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0, "left", 0.52, "half", "##C  Formula mechanism##   |   actual realization and bounded phase law"

    # --- Panel C mechanism field ---
    Select inner viewport: 0.75, 7.55, 5.60, 6.95
    Axes: 0, 1, 0, 1
    Paint rectangle: .bg$, 0, 1, 0, 1
    Colour: "{0.72, 0.72, 0.75}"
    Draw inner box

    Font size: 8
    Colour: .grey$
    Text: 0.5, "centre", 0.82, "half", "PARAMETERS  ->  FORMULA LAYERS  ->  SUM  ->  FADE  ->  SPATIAL RENDER  ->  OUTPUT"

    Font size: 8
    Colour: .blue$
    if synthesis_mode = 1
        Text: 0.5, "centre", 0.58, "half", "FM core: phase(t) = 2*pi*fc*t + beta*sin(2*pi*fm*t)"
    elsif synthesis_mode = 2
        Text: 0.5, "centre", 0.58, "half", "Three FM carriers compete at ratios 1 : phi : e"
    elsif synthesis_mode = 3
        Text: 0.5, "centre", 0.58, "half", "Nested PM: beta1*sin(2*pi*fm1*t + beta2*sin(2*pi*fm2*t))"
    elsif synthesis_mode = 4
        Text: 0.5, "centre", 0.58, "half", "Harmonic carriers: fk = k*f0 ; slow amplitude motion only"
    elsif synthesis_mode = 5
        Text: 0.5, "centre", 0.58, "half", "Fibonacci carriers: fk = f0 * {1, 2, 3, 5, 8, 13, ...}"
    else
        Text: 0.5, "centre", 0.58, "half", "Evolution: related carriers + bounded multi-rate FM + positive slow decay"
    endif

    Font size: 7
    Colour: .rust$
    Text: 0.5, "centre", 0.34, "half", realizedList$
    Colour: .grey$
    Text: 0.5, "centre", 0.13, "half", "Mod depth " + fixed$(modulation_depth, 2) + "   |   complexity " + fixed$(complexity_factor, 2) + "   |   evolution " + fixed$(evolution_speed, 2)

    # --- Summary / QC ---
    if spatial_mode = 2
        .spatial$ = "Stereo Wide"
    elsif spatial_mode = 3
        .spatial$ = "Rotating"
    else
        .spatial$ = "Mono"
    endif
    if random_seed > 0
        .seed$ = string$(random_seed)
    else
        .seed$ = "fresh"
    endif

    Select inner viewport: 0.65, 7.55, 7.16, 7.78
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "{0.72, 0.72, 0.72}"
    Draw inner box
    Font size: 7
    Colour: "{0.28, 0.28, 0.30}"
    Text: 0.5, "centre", 0.68, "half", "Peak " + fixed$(finalPeak, 3) + "   |   RMS " + fixed$(finalRms, 3) + "   |   model top " + fixed$(maxModelFreq, 0) + " Hz   |   " + .spatial$
    Text: 0.5, "centre", 0.30, "half", "Anti-alias reductions " + string$(antiAliasReductions) + "   |   skipped components " + string$(skippedComponents) + "   |   seed " + .seed$

    removeObject: .disp
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc
