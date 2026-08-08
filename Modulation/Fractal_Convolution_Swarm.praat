# ============================================================
# Praat AudioTools - Fractal Convolution Swarm.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Multi-scale delay processing with exponentially spaced delay groups.
#   Swarm mode is a sparse parallel delay-sum (FIR-style convolution with
#   delayed taps); Cascade mode applies the same causal delayed blend
#   recursively in successive stages. "Fractal" refers to the self-similar
#   delay scaling, not to FFT convolution or a physical-room model.
#
# Changelog v0.4:
#   - Corrected delay direction: taps are now causal delays, not advances.
#   - Depth 1 now equals Base_delay_ms; later depths scale from that base.
#   - Prevented negative kernel delays at wide convolution widths.
#   - Renamed Stereo -> Stereo_mode to avoid Praat's built-in "stereo"
#     identifier, which made the old control behave as Wide regardless of UI.
#   - Replaced unconditional peak normalization with attenuation-only
#     Safety_peak (0 disables); Mix_amount=0 is an exact dry bypass
#     apart from the documented mono-to-stereo output expansion.
#   - Swarm mode now builds a sparse impulse response and uses Praat
#     convolution for faster processing. Cascade remains sequential by design.
#   - Preserves multichannel inputs; >2-channel Swarm uses centered
#     per-channel wet taps instead of misrouting channels 2..N as "right".
#   - Added defensive limits and skip handling for taps beyond the signal.
#   - Rebuilt visualization text/layout to the AudioTools house standard.
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
duration = Get total duration
sampling = Get sampling frequency
srcStart = Get start time
nChannels = Get number of channels
nSamples = Get number of samples

# === Form ===
form Fractal Convolution Swarm
    comment Select a Sound object first

    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Subtle Texture
        option Ambient Swarm
        option Dense Cloud
        option Granular Dispersion
        option Extreme Fractal
        option Gentle Shimmer

    comment === Fractal Parameters ===
    natural Fractal_depth 5
    natural Convolution_width 3

    comment === Scaling ===
    positive Base_delay_ms 5.0
    positive Depth_scale_factor 1.6
    real Mix_amount 0.3
    comment (0 = dry only, 1 = maximum preset wet/send amount)

    comment === Processing ===
    optionmenu Processing 1
        option Swarm (parallel sparse delay sum)
        option Cascade (causal recursive dissolver)
    comment === Stereo Placement (Swarm only) ===
    optionmenu Stereo_mode 3
        option Centered
        option Wide (spread taps by kernel)
        option Ping-pong (bounce by depth)

    comment === Output ===
    real Safety_peak 0.99
    comment (0 disables; only attenuates when output exceeds the ceiling)
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    fractal_depth = 3
    convolution_width = 2
    base_delay_ms = 3.0
    depth_scale_factor = 1.4
    mix_amount = 0.2
    presetName$ = "Subtle Texture"
elsif preset = 3
    fractal_depth = 5
    convolution_width = 3
    base_delay_ms = 5.0
    depth_scale_factor = 1.6
    mix_amount = 0.3
    presetName$ = "Ambient Swarm"
elsif preset = 4
    fractal_depth = 6
    convolution_width = 4
    base_delay_ms = 7.0
    depth_scale_factor = 1.8
    mix_amount = 0.4
    presetName$ = "Dense Cloud"
elsif preset = 5
    fractal_depth = 7
    convolution_width = 5
    base_delay_ms = 8.0
    depth_scale_factor = 2.0
    mix_amount = 0.45
    presetName$ = "Granular Dispersion"
elsif preset = 6
    fractal_depth = 8
    convolution_width = 6
    base_delay_ms = 10.0
    depth_scale_factor = 2.2
    mix_amount = 0.5
    presetName$ = "Extreme Fractal"
elsif preset = 7
    fractal_depth = 4
    convolution_width = 2
    base_delay_ms = 2.5
    depth_scale_factor = 1.3
    mix_amount = 0.15
    presetName$ = "Gentle Shimmer"
else
    presetName$ = "Custom"
endif

# === Defensive Limits ===
fractal_depth = max(1, min(fractal_depth, 12))
convolution_width = max(1, min(convolution_width, 8))
depth_scale_factor = max(1, min(depth_scale_factor, 4))
mix_amount = max(0, min(mix_amount, 1))
safety_peak = max(0, min(safety_peak, 1))

if duration <= 0 or nSamples < 2
    exitScript: "Sound is too short."
endif

base_delay = max(1, round(base_delay_ms * sampling / 1000))

if processing = 2
    procName$ = "Cascade"
else
    procName$ = "Swarm"
endif

if stereo_mode = 2
    stereoName$ = "Wide"
elsif stereo_mode = 3
    stereoName$ = "Ping-pong"
else
    stereoName$ = "Centered"
endif

if processing = 2
    effectiveStereo$ = "n/a (Cascade)"
elsif nChannels > 2
    effectiveStereo$ = "Centered per-channel (>2ch)"
else
    effectiveStereo$ = stereoName$
endif

# === Info ===
writeInfoLine: "=== Fractal Convolution Swarm v0.4 ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Mode: ", procName$, " | Stereo: ", effectiveStereo$
appendInfoLine: "Channels: ", nChannels, " | Sample rate: ", round(sampling), " Hz"
appendInfoLine: ""
appendInfoLine: "Fractal depth: ", fractal_depth
appendInfoLine: "Convolution width: +/-", convolution_width
appendInfoLine: "Base delay: ", fixed$(base_delay_ms, 3), " ms"
appendInfoLine: "Scale factor: ", fixed$(depth_scale_factor, 3)
appendInfoLine: "Mix: ", fixed$(mix_amount, 3)
appendInfoLine: ""

# Store actual center-delay structure for visualization
delayTimes# = zero#(fractal_depth)
depthWeights# = zero#(fractal_depth)

for d from 1 to fractal_depth
    current_delay = max(1, round(base_delay * (depth_scale_factor ^ (d - 1))))
    delayTimes#[d] = current_delay / sampling * 1000
    depthWeights#[d] = 1 / sqrt(d)
endfor

# === Result Baseline ===
# Mono is intentionally expanded to stereo so Wide/Ping-pong have a target.
if nChannels = 1
    selectObject: original
    tmpL = Copy: "fcsTmpL"
    selectObject: original
    tmpR = Copy: "fcsTmpR"
    selectObject: tmpL, tmpR
    result = Combine to stereo
    removeObject: tmpL, tmpR
else
    selectObject: original
    result = Copy: originalName$ + "_fractal"
endif

selectObject: result
outChannels = Get number of channels

# Wet source used by mono/stereo Swarm panning.
wetSource = 0
if processing = 1 and nChannels <= 2
    if nChannels = 1
        wetSource = original
    else
        selectObject: original
        wetSource = Convert to mono
        Rename: "fcsWetMono"
    endif
endif

# === Build Fractal Tap Structure ===
appendInfoLine: "Building ", procName$, " tap structure..."

totalOperations = fractal_depth * (2 * convolution_width)
tapShift# = zero#(totalOperations)
tapGain# = zero#(totalOperations)
tapDepth# = zero#(totalOperations)
tapKernel# = zero#(totalOperations)
tapGL# = zero#(totalOperations)
tapGR# = zero#(totalOperations)

opCount = 0
skippedCount = 0
maxShift = 0

for depth from 1 to fractal_depth
    current_delay = max(1, round(base_delay * (depth_scale_factor ^ (depth - 1))))
    depth_weight = 1 / sqrt(depth)

    # Preserve the original +/-30% per-kernel spacing for widths <=3.
    # Wider kernels densify within +/-90% so delays never go negative.
    spread_scale = min(1, 3 / convolution_width)
    kernel_step = max(1, round(current_delay * 0.3 * spread_scale))

    appendInfoLine: "  Depth ", depth, "/", fractal_depth,
    ... " (center delay: ", fixed$(current_delay / sampling * 1000, 2), " ms)"

    for kernel from -convolution_width to convolution_width
        if kernel <> 0
            total_shift = current_delay + kernel * kernel_step
            total_shift = max(1, total_shift)

            if total_shift < nSamples
                opCount = opCount + 1
                kernel_weight = 1 / (1 + abs(kernel))
                gain = mix_amount * kernel_weight * depth_weight

                tapShift#[opCount] = total_shift
                tapGain#[opCount] = gain
                tapDepth#[opCount] = depth
                tapKernel#[opCount] = kernel

                if nChannels <= 2
                    if stereo_mode = 2
                        p = kernel / convolution_width
                    elsif stereo_mode = 3
                        if depth - 2 * floor(depth / 2) = 1
                            p = -1
                        else
                            p = 1
                        endif
                    else
                        p = 0
                    endif
                    panAngle = (p + 1) / 2 * pi / 2
                    tapGL#[opCount] = cos(panAngle)
                    tapGR#[opCount] = sin(panAngle)
                else
                    tapGL#[opCount] = 1
                    tapGR#[opCount] = 1
                endif

                if total_shift > maxShift
                    maxShift = total_shift
                endif
            else
                skippedCount = skippedCount + 1
            endif
        endif
    endfor
endfor

# === Apply Fractal Delay Structure ===
if mix_amount > 0 and opCount > 0
    if processing = 2
        # ---- CASCADE ----
        # Each operation reads earlier samples from the same evolving output.
        # It is intentionally sequential and recursive.
        for tap from 1 to opCount
            total_shift = round(tapShift#[tap])
            combined_weight = tapGain#[tap]
            dry_weight = 1 - combined_weight

            selectObject: result
            Formula: "self * " + string$(dry_weight) +
            ... " + (if col > " + string$(total_shift) +
            ... " then self[col - " + string$(total_shift) + "] * " +
            ... string$(combined_weight) + " else 0 fi)"
        endfor

    else
        # ---- SWARM ----
        # A parallel sparse delay sum is exactly convolution with a sparse
        # impulse response. Build that IR once and use Praat's convolution,
        # instead of making one full-buffer Formula pass per tap.
        irSamples = maxShift + 1
        irDur = irSamples / sampling

        if nChannels <= 2
            Create Sound from formula: "fcsIRL", 1, 0, irDur, sampling, "0"
            irL = selected("Sound")
            Create Sound from formula: "fcsIRR", 1, 0, irDur, sampling, "0"
            irR = selected("Sound")

            for tap from 1 to opCount
                sampleIndex = round(tapShift#[tap]) + 1

                selectObject: irL
                oldL = Get value at sample number: 1, sampleIndex
                Set value at sample number: 1, sampleIndex,
                ... oldL + tapGain#[tap] * tapGL#[tap]

                selectObject: irR
                oldR = Get value at sample number: 1, sampleIndex
                Set value at sample number: 1, sampleIndex,
                ... oldR + tapGain#[tap] * tapGR#[tap]
            endfor

            selectObject: wetSource, irL
            wetLFull = Convolve: "sum", "zero"

            selectObject: wetSource, irR
            wetRFull = Convolve: "sum", "zero"

            # Convolution starts at the source start time; the first nSamples
            # columns align with the original. Read those columns directly,
            # avoiding Extract-part boundary rounding.
            selectObject: result
            Formula: "self + (if row = 1 then object[" + string$(wetLFull) +
            ... ", 1, col] else object[" + string$(wetRFull) + ", 1, col] fi)"

            removeObject: irL, irR, wetLFull, wetRFull

        else
            # No speaker-layout assumption for >2 channels: use one centered
            # sparse IR independently on every source channel.
            Create Sound from formula: "fcsIRC", 1, 0, irDur, sampling, "0"
            irC = selected("Sound")

            for tap from 1 to opCount
                sampleIndex = round(tapShift#[tap]) + 1
                selectObject: irC
                oldC = Get value at sample number: 1, sampleIndex
                Set value at sample number: 1, sampleIndex,
                ... oldC + tapGain#[tap]
            endfor

            for ch from 1 to nChannels
                selectObject: original
                Extract one channel: ch
                chDry = selected("Sound")

                selectObject: chDry, irC
                wetFull = Convolve: "sum", "zero"

                selectObject: result
                Formula (part): srcStart, srcStart + duration, ch, ch,
                ... "self + object[" + string$(wetFull) + ", 1, col]"

                removeObject: chDry, wetFull
            endfor

            removeObject: irC
        endif
    endif

elsif mix_amount = 0
    appendInfoLine: "Mix = 0: exact dry bypass."
else
    appendInfoLine: "No valid taps fit inside this sound; output is dry."
endif

if wetSource <> 0 and wetSource <> original
    removeObject: wetSource
endif

appendInfoLine: ""
appendInfoLine: "Active taps/operations: ", opCount
if skippedCount > 0
    appendInfoLine: "Skipped (delay >= signal): ", skippedCount, " / ", totalOperations
endif

# === Safety Output Stage ===
selectObject: result
preSafetyPeak = Get absolute extremum: 0, 0, "None"
safetyAction$ = "none"
if mix_amount = 0
    safetyAction$ = "bypassed with dry path"
elsif safety_peak > 0 and preSafetyPeak > safety_peak and preSafetyPeak > 0
    Scale peak: safety_peak
    safetyAction$ = "attenuated to " + fixed$(safety_peak, 3)
elsif safety_peak > 0
    safetyAction$ = "not needed"
else
    safetyAction$ = "disabled"
endif

Rename: originalName$ + "_fractal_" + presetName$
finalName$ = selected$("Sound")
outPeak = Get absolute extremum: 0, 0, "None"

# === Visualization ===
if draw_visualization
    Erase all

    # === TITLE + METADATA ===
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Fractal Convolution Swarm##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -1.30, "half",
    ... originalName$ + "  |  " + presetName$ + "  |  " + procName$ +
    ... "  |  " + effectiveStereo$

    # === INPUT ===
    Select outer viewport: 0, 8, 0.65, 1.45
    Select inner viewport: 0.6, 7.7, 0.72, 1.36
    selectObject: original
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"

    # === OUTPUT ===
    Select outer viewport: 0, 8, 1.55, 2.35
    Select inner viewport: 0.6, 7.7, 1.62, 2.26
    selectObject: result
    Colour: "{0.22, 0.45, 0.80}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"

    # === DEPTH DELAYS ===
    Select outer viewport: 0, 4, 2.55, 3.85
    Select inner viewport: 0.6, 3.75, 2.70, 3.72
    maxDelay = delayTimes#[fractal_depth]
    Axes: 0, fractal_depth + 1, 0, max(1, maxDelay * 1.1)
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, fractal_depth + 1, 0, max(1, maxDelay * 1.1)
    for d from 1 to fractal_depth
        Paint rectangle: "{0.46, 0.35, 0.74}", d - 0.35, d + 0.35, 0, delayTimes#[d]
    endfor
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Delay (ms)"
    Text bottom: "yes", "Depth"

    # === DEPTH WEIGHTS ===
    Select outer viewport: 4, 8, 2.55, 3.85
    Select inner viewport: 4.45, 7.65, 2.70, 3.72
    Axes: 0, fractal_depth + 1, 0, 1.1
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, fractal_depth + 1, 0, 1.1
    for d from 1 to fractal_depth
        Paint rectangle: "{0.30, 0.50, 0.82}", d - 0.35, d + 0.35, 0, depthWeights#[d]
    endfor
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Weight"
    Text bottom: "yes", "Depth"

    # === KERNEL WEIGHTS ===
    Select outer viewport: 0, 8, 4.05, 4.85
    Select inner viewport: 0.6, 7.7, 4.15, 4.75
    Axes: -convolution_width - 1, convolution_width + 1, 0, 1.1
    Paint rectangle: "{0.97, 0.97, 0.98}", -convolution_width - 1, convolution_width + 1, 0, 1.1
    for k from -convolution_width to convolution_width
        if k = 0
            kWeight = 1
            Paint rectangle: "{0.75, 0.75, 0.75}", k - 0.35, k + 0.35, 0, kWeight
        else
            kWeight = 1 / (1 + abs(k))
            Paint rectangle: "{0.52, 0.35, 0.72}", k - 0.35, k + 0.35, 0, kWeight
        endif
    endfor
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Kernel"
    Text bottom: "yes", "Offset"

    # === SUMMARY ===
    Select outer viewport: 0, 8, 5.00, 5.65
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.80, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.50, "half",
    ... "Mode: " + procName$ + "  |  Stereo: " + effectiveStereo$ +
    ... "  |  Depth: " + string$(fractal_depth) +
    ... "  |  Width: +/-" + string$(convolution_width) +
    ... "  |  Mix: " + fixed$(mix_amount, 2)
    Text: 0.02, "left", 0.18, "half",
    ... "Base: " + fixed$(delayTimes#[1], 2) + " ms" +
    ... "  |  Scale: x" + fixed$(depth_scale_factor, 2) +
    ... "  |  Max depth delay: " + fixed$(maxDelay, 1) + " ms" +
    ... "  |  Active: " + string$(opCount) +
    ... "  |  Safety: " + safetyAction$
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# === Final Info ===
selectObject: result
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", finalName$
appendInfoLine: "Peak before safety: ", fixed$(preSafetyPeak, 6)
appendInfoLine: "Output peak: ", fixed$(outPeak, 6)
appendInfoLine: "Safety: ", safetyAction$

if play_result
    selectObject: result
    Play
endif

selectObject: result
