# ============================================================
# Praat AudioTools - Stereo_Shimmer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 reviewed (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Stereo shimmer-like multi-tap ambience with linearly spaced,
#   independently jittered delays, alternating polarity, subtle
#   left/right decorrelation, and high-frequency emphasis.
#
#   The effect deliberately preserves the AudioTools character of the
#   original script. It is not a pitch-transposing octave shimmer;
#   "shimmer" here refers to the bright, spatial multi-tap texture.
#
# Review changes v1.1:
#   - Replaced recursive self(x-delay) cascade with true independent taps.
#   - The tap times used by DSP are generated once and reused by the plot.
#   - Prevents negative/zero delays when jitter exceeds the minimum delay.
#   - Wet path is truly wet: no hidden unity direct signal.
#   - HF enhancement is calculated from a frozen copy (non-recursive).
#   - Speed modes downsample only the wet-processing path; dry stays full-rate.
#   - Mono input now produces a real stereo shimmer field.
#   - Removed repeated/per-channel Scale peak normalization.
#   - Added one common down-only peak safeguard after stereo combining.
#   - Fixed Sound object access by using time-based object(id, x, channel).
#   - Ensures the output tail is long enough for the latest tap.
#   - Visualization updated to the Praat AudioTools house style.
# ============================================================

form Stereo Shimmer
    comment Select a Sound object first

    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Subtle Shimmer
        option Medium Shimmer
        option Heavy Shimmer
        option Extreme Shimmer

    comment === Performance ===
    optionmenu Speed_mode 2
        option Full Quality (wet at original sample rate)
        option Balanced (wet at 22.05 kHz)
        option Fast (wet at 11.025 kHz)

    comment === Shimmer Parameters ===
    positive Tail_duration_s 2
    natural Number_of_echoes 80
    positive Base_amplitude 0.24
    positive Min_delay_s 0.02
    positive Max_delay_s 1.2
    positive Decay_factor 0.95
    positive Jitter_s 0.012

    comment === HF Enhancement ===
    positive HF_enhancement 0.25

    comment === Mix ===
    real Wet_dry_percent 60
    comment (0 = dry only, 100 = wet only)

    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# INPUT / PRESETS
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
originalDur = Get total duration
originalStart = Get start time
sampleRate = Get sampling frequency
numChannels = Get number of channels

if numChannels <> 1 and numChannels <> 2
    exitScript: "Stereo Shimmer currently supports mono or stereo Sound objects only."
endif

if preset = 2
    tail_duration_s = 1.5
    number_of_echoes = 40
    base_amplitude = 0.15
    min_delay_s = 0.02
    max_delay_s = 0.8
    decay_factor = 0.96
    jitter_s = 0.008
    hF_enhancement = 0.15
    presetName$ = "Subtle"
elsif preset = 3
    tail_duration_s = 2
    number_of_echoes = 80
    base_amplitude = 0.24
    min_delay_s = 0.02
    max_delay_s = 1.2
    decay_factor = 0.95
    jitter_s = 0.012
    hF_enhancement = 0.25
    presetName$ = "Medium"
elsif preset = 4
    tail_duration_s = 3
    number_of_echoes = 120
    base_amplitude = 0.32
    min_delay_s = 0.015
    max_delay_s = 1.8
    decay_factor = 0.94
    jitter_s = 0.018
    hF_enhancement = 0.35
    presetName$ = "Heavy"
elsif preset = 5
    tail_duration_s = 4
    number_of_echoes = 180
    base_amplitude = 0.4
    min_delay_s = 0.01
    max_delay_s = 2.5
    decay_factor = 0.93
    jitter_s = 0.025
    hF_enhancement = 0.45
    presetName$ = "Extreme"
else
    presetName$ = "Custom"
endif

# ============================================================
# VALIDATION / PERFORMANCE MODE
# ============================================================

if number_of_echoes < 1
    exitScript: "Number of echoes must be at least 1."
endif

if max_delay_s < min_delay_s
    exitScript: "Max delay must be greater than or equal to Min delay."
endif

if base_amplitude >= 1
    exitScript: "Base amplitude must be below 1.0 for this multi-tap effect."
endif

if decay_factor >= 1
    exitScript: "Decay factor must be below 1.0 so later taps decay."
endif

if jitter_s < 0
    jitter_s = 0
endif

if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif

wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

if speed_mode = 1
    targetSR = sampleRate
    speedStr$ = "Full Quality"
elsif speed_mode = 2
    targetSR = 22050
    speedStr$ = "Balanced"
else
    targetSR = 11025
    speedStr$ = "Fast"
endif

# Never upsample merely for processing.
if targetSR > sampleRate
    targetSR = sampleRate
endif

startTime = stopwatch

# ============================================================
# GENERATE ACTUAL TAP PARAMETERS ONCE
# ============================================================

# Generate using the eventual wet-path sample rate so that the minimum
# delay is always safely positive at that rate.
halfSample = 0.5 / targetSR
maxActualDelay = 0

# Slightly stronger right-channel decorrelation, preserving the original idea.
# Bound jitter by the minimum delay so no tap collapses to an almost-zero
# or negative delay in Heavy/Extreme presets.
effectiveJitterL = jitter_s
jitterLimit = 0.8 * min_delay_s
if effectiveJitterL > jitterLimit
    effectiveJitterL = jitterLimit
endif

effectiveJitterR = jitter_s * 1.25
if effectiveJitterR > jitterLimit
    effectiveJitterR = jitterLimit
endif

decayR = decay_factor - 0.01
if decayR <= 0
    decayR = 0.001
endif

for k from 1 to number_of_echoes
    if number_of_echoes = 1
        nominalDelay = min_delay_s
    else
        nominalDelay = min_delay_s + (max_delay_s - min_delay_s) * (k - 1) / (number_of_echoes - 1)
    endif

    delayL = nominalDelay + randomUniform(-effectiveJitterL, effectiveJitterL)
    delayR = nominalDelay + randomUniform(-effectiveJitterR, effectiveJitterR)

    if delayL < halfSample
        delayL = halfSample
    endif
    if delayR < halfSample
        delayR = halfSample
    endif

    if k mod 4 < 2
        polarityL = 1
    else
        polarityL = -1
    endif

    if (k + 2) mod 4 < 2
        polarityR = 1
    else
        polarityR = -1
    endif

    ampL = base_amplitude * (decay_factor ^ k) * polarityL
    ampR = base_amplitude * (decayR ^ k) * polarityR

    echoDelayL[k] = delayL
    echoDelayR[k] = delayR
    echoAmpL[k] = ampL
    echoAmpR[k] = ampR

    if delayL > maxActualDelay
        maxActualDelay = delayL
    endif
    if delayR > maxActualDelay
        maxActualDelay = delayR
    endif
endfor

# Never truncate the latest independent tap. The user tail remains the
# minimum requested tail beyond the dry source.
effectiveTail = tail_duration_s
if effectiveTail < maxActualDelay
    effectiveTail = maxActualDelay
endif

totalDur = originalDur + effectiveTail

# ============================================================
# INFO
# ============================================================

writeInfoLine: "=== Stereo Shimmer ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Speed: ", speedStr$, " (wet path ", fixed$(targetSR, 0), " Hz)"
appendInfoLine: ""
appendInfoLine: "Taps per side: ", number_of_echoes
appendInfoLine: "Nominal delay range: ", fixed$(min_delay_s * 1000, 1), " - ", fixed$(max_delay_s * 1000, 1), " ms"
appendInfoLine: "Latest actual tap: ", fixed$(maxActualDelay * 1000, 1), " ms"
appendInfoLine: "Decay: ", fixed$(decay_factor, 3)
appendInfoLine: "Requested jitter: +/-", fixed$(jitter_s * 1000, 1), " ms"
appendInfoLine: "Effective jitter L/R: +/-", fixed$(effectiveJitterL * 1000, 1), " / +/-", fixed$(effectiveJitterR * 1000, 1), " ms"
appendInfoLine: "HF enhancement: ", fixed$(hF_enhancement, 2)
appendInfoLine: "Wet/Dry: ", fixed$(wet_dry_percent, 0), "%"
appendInfoLine: "Output tail: ", fixed$(effectiveTail, 2), " s"
appendInfoLine: ""

# ============================================================
# TRUE DRY-ONLY FAST PATH
# ============================================================

if wet_level = 0
    if numChannels = 2
        selectObject: original
        Copy: originalName$ + "_shimmer_" + presetName$
        result = selected("Sound")
    else
        selectObject: original
        Copy: "shimmer_dry_left"
        dryLeftZero = selected("Sound")

        selectObject: original
        Copy: "shimmer_dry_right"
        dryRightZero = selected("Sound")

        selectObject: dryLeftZero, dryRightZero
        Combine to stereo
        result = selected("Sound")
        Rename: originalName$ + "_shimmer_" + presetName$

        removeObject: dryLeftZero, dryRightZero
    endif

else
    appendInfoLine: "Processing..."

    # ========================================================
    # PREPARE FULL-RATE DRY CHANNELS (TIME ORIGIN = 0)
    # ========================================================

    if numChannels = 2
        selectObject: original
        Extract one channel: 1
        dryLeft = selected("Sound")

        selectObject: original
        Extract one channel: 2
        dryRight = selected("Sound")
    else
        selectObject: original
        Copy: "shimmer_dry_left"
        dryLeft = selected("Sound")

        selectObject: original
        Copy: "shimmer_dry_right"
        dryRight = selected("Sound")
    endif

    if originalStart <> 0
        selectObject: dryLeft
        Shift times by: -originalStart
        selectObject: dryRight
        Shift times by: -originalStart
    endif

    # ========================================================
    # PREPARE WET SOURCE (OPTIONALLY DOWNSAMPLED)
    # ========================================================

    selectObject: original
    Copy: "shimmer_working"
    workingSound = selected("Sound")

    if originalStart <> 0
        Shift times by: -originalStart
    endif

    if sampleRate > targetSR
        selectObject: workingSound
        Resample: targetSR, 50
        resampledWorking = selected("Sound")
        removeObject: workingSound
        workingSound = resampledWorking
    endif

    workingSR = targetSR
    samplePeriod = 1 / workingSR

    # Extend the wet source with a zero tail. Independent taps read from
    # this immutable source and are accumulated into separate wet buffers.
    if numChannels = 2
        Create Sound from formula: "shimmer_tail", 2, 0, effectiveTail, workingSR, "0"
    else
        Create Sound from formula: "shimmer_tail", 1, 0, effectiveTail, workingSR, "0"
    endif
    silentTail = selected("Sound")

    selectObject: workingSound, silentTail
    Concatenate
    extendedSource = selected("Sound")
    removeObject: silentTail

    if numChannels = 2
        selectObject: extendedSource
        Extract one channel: 1
        wetSourceLeft = selected("Sound")

        selectObject: extendedSource
        Extract one channel: 2
        wetSourceRight = selected("Sound")
    else
        selectObject: extendedSource
        Copy: "shimmer_wetsource_left"
        wetSourceLeft = selected("Sound")

        selectObject: extendedSource
        Copy: "shimmer_wetsource_right"
        wetSourceRight = selected("Sound")
    endif

    # ========================================================
    # ACCUMULATE TRUE INDEPENDENT TAPS
    # ========================================================

    Create Sound from formula: "shimmer_wet_left", 1, 0, totalDur, workingSR, "0"
    wetLeft = selected("Sound")

    Create Sound from formula: "shimmer_wet_right", 1, 0, totalDur, workingSR, "0"
    wetRight = selected("Sound")

    leftSourceStr$ = string$(wetSourceLeft)
    rightSourceStr$ = string$(wetSourceRight)

    for k from 1 to number_of_echoes
        delayLStr$ = string$(echoDelayL[k])
        delayRStr$ = string$(echoDelayR[k])
        ampLStr$ = string$(echoAmpL[k])
        ampRStr$ = string$(echoAmpR[k])

        selectObject: wetLeft
        Formula: "self + " + ampLStr$ + " * object(" + leftSourceStr$ + ", x - " + delayLStr$ + ", 1)"

        selectObject: wetRight
        Formula: "self + " + ampRStr$ + " * object(" + rightSourceStr$ + ", x - " + delayRStr$ + ", 1)"

        if k mod 40 = 0
            appendInfoLine: "  Taps: ", k, "/", number_of_echoes
        endif
    endfor

    # ========================================================
    # NON-RECURSIVE HF ENHANCEMENT ON WET ONLY
    # ========================================================

    selectObject: wetLeft
    Copy: "shimmer_wet_left_frozen"
    wetLeftFrozen = selected("Sound")

    selectObject: wetRight
    Copy: "shimmer_wet_right_frozen"
    wetRightFrozen = selected("Sound")

    leftFrozenStr$ = string$(wetLeftFrozen)
    rightFrozenStr$ = string$(wetRightFrozen)
    spStr$ = string$(samplePeriod)
    hfLStr$ = string$(hF_enhancement)
    hfR = hF_enhancement * 0.92
    hfRStr$ = string$(hfR)

    selectObject: wetLeft
    Formula: "object(" + leftFrozenStr$ + ", x, 1) + " + hfLStr$ + " * (object(" + leftFrozenStr$ + ", x, 1) - object(" + leftFrozenStr$ + ", x - " + spStr$ + ", 1))"

    selectObject: wetRight
    Formula: "object(" + rightFrozenStr$ + ", x, 1) + " + hfRStr$ + " * (object(" + rightFrozenStr$ + ", x, 1) - object(" + rightFrozenStr$ + ", x - " + spStr$ + ", 1))"

    removeObject: wetLeftFrozen, wetRightFrozen

    # ========================================================
    # RETURN WET TO ORIGINAL SAMPLE RATE BEFORE MIXING
    # ========================================================

    if workingSR <> sampleRate
        selectObject: wetLeft
        Resample: sampleRate, 50
        wetLeftFull = selected("Sound")
        removeObject: wetLeft
        wetLeft = wetLeftFull

        selectObject: wetRight
        Resample: sampleRate, 50
        wetRightFull = selected("Sound")
        removeObject: wetRight
        wetRight = wetRightFull
    endif

    # ========================================================
    # TRUE WET/DRY MIX AT ORIGINAL SAMPLE RATE
    # ========================================================

    wetStr$ = string$(wet_level)
    dryStr$ = string$(dry_level)
    dryLeftStr$ = string$(dryLeft)
    dryRightStr$ = string$(dryRight)

    selectObject: wetLeft
    Formula: "self * " + wetStr$ + " + object(" + dryLeftStr$ + ", x, 1) * " + dryStr$

    selectObject: wetRight
    Formula: "self * " + wetStr$ + " + object(" + dryRightStr$ + ", x, 1) * " + dryStr$

    selectObject: wetLeft, wetRight
    Combine to stereo
    result = selected("Sound")
    Rename: originalName$ + "_shimmer_" + presetName$

    # Common down-only safeguard; never boost quiet material.
    selectObject: result
    resultPeak = Get absolute extremum: 0, 0, "none"
    if resultPeak > 1
        Scale peak: 0.98
    endif

    removeObject: dryLeft, dryRight, workingSound, extendedSource, wetSourceLeft, wetSourceRight, wetLeft, wetRight
endif

selectObject: result
resultDur = Get total duration
processingTime = stopwatch - startTime

# ============================================================
# VISUALIZATION - PRAAT AUDIOTOOLS HOUSE STYLE
# ============================================================

if draw_visualization
    Erase all

    # Main title.
    Select outer viewport: 0, 8, 0.05, 0.38
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.58, "half", "Stereo Shimmer | " + presetName$

    # Metadata line.
    Select outer viewport: 0, 8, 0.36, 0.58
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.35, 0.35, 0.35}"
    Text: 0.5, "centre", 0.5, "half", originalName$ + " | " + string$(number_of_echoes) + " taps/side | Wet " + fixed$(wet_dry_percent, 0) + "% | " + speedStr$

    # Dry waveform, on the full output time axis.
    Select outer viewport: 0, 8, 0.65, 1.35
    Select inner viewport: 0.65, 7.65, 0.72, 1.28
    selectObject: original
    Colour: "{0.65, 0.65, 0.65}"
    Draw: originalStart, originalStart + resultDur, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Dry"

    # Output waveform including the full tail.
    Select outer viewport: 0, 8, 1.42, 2.12
    Select inner viewport: 0.65, 7.65, 1.49, 2.05
    selectObject: result
    Colour: "{0.58, 0.50, 0.72}"
    Draw: 0, resultDur, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"

    # Tap-field title.
    Select outer viewport: 0, 8, 2.24, 2.48
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Independent stereo tap field"

    # Actual delays and signed amplitudes used by DSP.
    Select outer viewport: 0, 8, 2.45, 3.84
    Select inner viewport: 0.65, 7.65, 2.60, 3.69

    maxDelayMs = maxActualDelay * 1000 * 1.05
    maxAmp = base_amplitude * 1.15
    Axes: 0, maxDelayMs, -maxAmp, maxAmp
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, maxDelayMs, -maxAmp, maxAmp

    Colour: "{0.84, 0.84, 0.84}"
    Draw line: 0, 0, maxDelayMs, 0

    # Show at most 120 points per side for a legible plot.
    showEvery = ceiling(number_of_echoes / 120)
    if showEvery < 1
        showEvery = 1
    endif

    for k from 1 to number_of_echoes
        if k mod showEvery = 0 or k = 1 or k = number_of_echoes
            xL = echoDelayL[k] * 1000
            xR = echoDelayR[k] * 1000
            yL = echoAmpL[k]
            yR = echoAmpR[k]

            Colour: "{0.42, 0.58, 0.76}"
            Draw line: xL, 0, xL, yL
            Paint circle (mm): "{0.42, 0.58, 0.76}", xL, yL, 0.75

            Colour: "{0.76, 0.47, 0.52}"
            Draw line: xR, 0, xR, yR
            Paint circle (mm): "{0.76, 0.47, 0.52}", xR, yR, 0.75
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Signed amplitude"
    Text bottom: "yes", "Delay (ms)"

    Font size: 5
    Colour: "{0.42, 0.58, 0.76}"
    Text: maxDelayMs * 0.96, "right", maxAmp * 0.88, "half", "LEFT"
    Colour: "{0.76, 0.47, 0.52}"
    Text: maxDelayMs * 0.96, "right", maxAmp * 0.68, "half", "RIGHT"

    # Summary panel.
    Select outer viewport: 0.35, 7.65, 3.95, 4.48
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.35}"
    Font size: 6
    Text: 0.5, "centre", 0.68, "half", "Delay " + fixed$(min_delay_s * 1000, 0) + "-" + fixed$(max_delay_s * 1000, 0) + " ms | Decay " + fixed$(decay_factor, 3) + " | Jitter +/-" + fixed$(effectiveJitterL * 1000, 1) + " ms"
    Text: 0.5, "centre", 0.30, "half", "HF " + fixed$(hF_enhancement, 2) + " | Tail " + fixed$(effectiveTail, 2) + " s | Wet path " + fixed$(targetSR / 1000, 2) + " kHz | Process " + fixed$(processingTime, 2) + " s"

    Font size: 10
    Colour: "Black"
endif

# ============================================================
# FINAL INFO / PLAY
# ============================================================

selectObject: result
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Processing time: ", fixed$(processingTime, 2), " seconds"
appendInfoLine: "Output duration: ", fixed$(resultDur, 3), " s"
appendInfoLine: "Created: ", selected$("Sound")

if play_result
    Play
endif

selectObject: result
