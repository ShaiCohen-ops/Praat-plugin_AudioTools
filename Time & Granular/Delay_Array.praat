# ============================================================
# Praat AudioTools - Delay_Array.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Delay Array - iteratively applies an FIR high-pass comb,
#   output[n] = input[n+delay] - input[n] (zero at DC).
#   Default "divisor" mode sets delay = floor(totalSamples/divisor),
#   a fraction of the file, so notch spacing is only divisor/duration Hz
#   (sub-Hz..tens of Hz) -> perceptually broadband decorrelation, not
#   tonal comb. Enable Use_ms_delay for short delays that give audible
#   comb filtering. Finite-signal boundaries use zero-padding.
#
# Multiple iterations create complex spectral interference patterns.
#
# Changelog v0.4.1:
#   - Visualization-only alignment to the current Praat AudioTools suite.
#   - Reframed as Source -> Delay cascade map -> Output -> Summary.
#   - Central diagram now directly embodies each FIR difference stage,
#     x[n+D] - x[n], with the active delay and comb spacing per iteration.
#   - Unified panel geometry, typography, neutral backgrounds and filename
#     display; DSP, presets, delay calculations and processing are unchanged.
#
# Changelog v0.4:
#   - FIR boundary handling corrected. Out-of-range delayed samples now use
#     Praat's documented zero value, so every sample obeys the same
#     x[n+D] - x[n] operator. v0.3 kept the original tail unfiltered,
#     breaking the comb response near the end on every iteration.
#   - Presets now define both divisor-mode and millisecond-mode delays.
#     Previously every preset sounded identical when Use_ms_delay was ON.
#   - Active delays are validated to be shorter than the Sound, preventing
#     no-op / degenerate passes where there is no source overlap.
#   - Number_of_iterations > 4 now reports an error instead of silently
#     changing the requested value.
#   - Scale_peak is validated to (0, 1]; silent results are not normalized.
#   - Info reports comb spacing (first non-DC zero spacing) and displays the
#     active delay mode instead of always labelling values as divisors.
#   - Spectrum visualization is capped at Nyquist for low sample rates.
#   - Added preset/mode names to output and visualization metadata.
#
# Changelog v0.3:
#   - else-branch now keeps the original sample instead of zeroing it
#     (was silencing the last 1/divisor each iteration; half the file
#     at divisor 2).
#   - Added optional millisecond-delay mode (Use_ms_delay, off by default)
#     for audible comb filtering; divisor mode unchanged when off.
#   - Iterations clamped to 4 (only four divisor/ms fields exist; higher
#     values referenced undefined divisors and crashed).
#   - Viz: spectra computed on a mono fold (To Spectrum is mono-only);
#     legend drawn in normalized axes.
#   - Description corrected to describe the actual effect.
#
# Changelog v0.2:
#   - Modern syntax
#   - Added visualization
#   - Added play option
#   - Bounds checking
# ============================================================

form Delay Array v0.4.1
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Default (2, 4, 8, 10)
        option Fine (2, 3, 5, 7)
        option Coarse (4, 8, 12, 16)
        option Extreme (2, 6, 12, 24)
        option Harmonic (2, 4, 8, 16)
        option Prime (2, 3, 5, 11)
        option Custom
    
    comment === Divisors ===
    positive Divisor_1 2
    positive Divisor_2 4
    positive Divisor_3 8
    positive Divisor_4 10
    
    comment === Iterations ===
    natural Number_of_iterations 4
    
    comment === Delay Mode ===
    boolean Use_ms_delay 0
    positive Delay_1_ms 3
    positive Delay_2_ms 5
    positive Delay_3_ms 7
    positive Delay_4_ms 11
    
    comment === Output ===
    positive Scale_peak 0.99
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
presetName$ = "Custom"
if preset = 1
    divisor_1 = 2
    divisor_2 = 4
    divisor_3 = 8
    divisor_4 = 10
    delay_1_ms = 2
    delay_2_ms = 4
    delay_3_ms = 8
    delay_4_ms = 10
    presetName$ = "Default"
elsif preset = 2
    divisor_1 = 2
    divisor_2 = 3
    divisor_3 = 5
    divisor_4 = 7
    delay_1_ms = 2
    delay_2_ms = 3
    delay_3_ms = 5
    delay_4_ms = 7
    presetName$ = "Fine"
elsif preset = 3
    divisor_1 = 4
    divisor_2 = 8
    divisor_3 = 12
    divisor_4 = 16
    delay_1_ms = 4
    delay_2_ms = 8
    delay_3_ms = 12
    delay_4_ms = 16
    presetName$ = "Coarse"
elsif preset = 4
    divisor_1 = 2
    divisor_2 = 6
    divisor_3 = 12
    divisor_4 = 24
    delay_1_ms = 2
    delay_2_ms = 6
    delay_3_ms = 12
    delay_4_ms = 24
    presetName$ = "Extreme"
elsif preset = 5
    divisor_1 = 2
    divisor_2 = 4
    divisor_3 = 8
    divisor_4 = 16
    delay_1_ms = 2
    delay_2_ms = 4
    delay_3_ms = 8
    delay_4_ms = 16
    presetName$ = "Harmonic"
elsif preset = 6
    divisor_1 = 2
    divisor_2 = 3
    divisor_3 = 5
    divisor_4 = 11
    delay_1_ms = 2
    delay_2_ms = 3
    delay_3_ms = 5
    delay_4_ms = 11
    presetName$ = "Prime"
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
totalSamples = Get number of samples
sampleRate = Get sampling frequency
duration = Get total duration

# Validate parameters
if number_of_iterations > 4
    exitScript: "Number of iterations must be between 1 and 4."
endif
if scale_peak <= 0 or scale_peak > 1
    exitScript: "Scale peak must be > 0 and <= 1."
endif

# Store divisors in array
divisor[1] = divisor_1
divisor[2] = divisor_2
divisor[3] = divisor_3
divisor[4] = divisor_4

# Store ms values in array
msVal[1] = delay_1_ms
msVal[2] = delay_2_ms
msVal[3] = delay_3_ms
msVal[4] = delay_4_ms

# Precompute per-iteration delay (samples), >=1 and < Sound length.
if use_ms_delay
    delayMode$ = "milliseconds"
else
    delayMode$ = "file divisor"
endif

for k to number_of_iterations
    if use_ms_delay
        delayArr[k] = round(msVal[k] / 1000 * sampleRate)
    else
        if divisor[k] <= 1
            exitScript: "Active divisors must be > 1 so the delay is shorter than the Sound."
        endif
        delayArr[k] = floor(totalSamples / divisor[k])
    endif
    if delayArr[k] < 1
        delayArr[k] = 1
    endif
    if delayArr[k] >= totalSamples
        exitScript: "Delay in iteration " + string$(k) + " is as long as or longer than the Sound."
    endif
endfor

# === Info ===
writeInfoLine: "=== Delay Array ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Samples: ", totalSamples
appendInfoLine: ""
appendInfoLine: "Preset: ", presetName$, " | Delay mode: ", delayMode$
appendInfoLine: "Iterations: ", number_of_iterations
appendInfoLine: ""
if use_ms_delay
    appendInfoLine: "Iter | Requested ms | Delay samples | Actual ms | Comb spacing"
    appendInfoLine: "-----|--------------|---------------|-----------|-------------"
else
    appendInfoLine: "Iter | Divisor | Delay samples | Actual ms | Comb spacing"
    appendInfoLine: "-----|---------|---------------|-----------|-------------"
endif

for k to number_of_iterations
    delaySamples = delayArr[k]
    delayMs = delaySamples / sampleRate * 1000
    combSpacing = sampleRate / delaySamples
    if use_ms_delay
        appendInfoLine: "  ", k, "  |    ", fixed$(msVal[k], 3), "     |     ", delaySamples, "      |  ", fixed$(delayMs, 3), "  |  ", fixed$(combSpacing, 2), " Hz"
    else
        appendInfoLine: "  ", k, "  |   ", fixed$(divisor[k], 3), "   |     ", delaySamples, "      |  ", fixed$(delayMs, 3), "  |  ", fixed$(combSpacing, 2), " Hz"
    endif
endfor
appendInfoLine: ""

# === Copy Sound ===
selectObject: original
if use_ms_delay
    modeTag$ = "ms"
else
    modeTag$ = "div"
endif
Copy: original_name$ + "_delayArray_" + presetName$ + "_" + modeTag$
result = selected("Sound")

# === Apply Delay Differencing ===
appendInfoLine: "Processing..."

for k to number_of_iterations
    selectObject: result
    delaySamples = delayArr[k]
    
    # Uniform FIR difference across the full Sound. Praat returns 0 for
    # self[index] outside 1..ncol, giving principled zero-padding at the edge.
    # Using a future sample also avoids accidental recursion during in-place Formula.
    Formula: "self[col + delaySamples] - self[col]"
    
    appendInfoLine: "  Iteration ", k, " done"
endfor

# === Scale Peak ===
selectObject: result
resultPeak = Get absolute extremum: 0, 0, "Sinc70"
if resultPeak > 0
    Scale peak: scale_peak
endif

# ============================================================
# VISUALIZATION  (current Praat AudioTools suite styling)
# Source -> Delay cascade map -> Output -> Summary.
# The central diagram directly embodies the repeated FIR law:
#   stage_k[n] = stage_(k-1)[n + D_k] - stage_(k-1)[n]
# Orange boxes = the repeated delay-difference operation.
# ============================================================
if draw_visualization
    Erase all
    Select outer viewport: 0, 8, 0, 7.10
    Black
    Plain line

    displayName$ = replace$(original_name$, "_", " ", 0)

    # Mono, zero-based display copies.
    selectObject: original
    vizOrig = Convert to mono
    selectObject: vizOrig
    vizOrigStart = Get start time
    Shift times by: -vizOrigStart

    selectObject: result
    vizResult = Convert to mono
    selectObject: vizResult
    vizResultStart = Get start time
    Shift times by: -vizResultStart

    # Shared source/output amplitude scale.
    selectObject: vizOrig
    origPeak = Get absolute extremum: 0, 0, "None"
    selectObject: vizResult
    outPeak = Get absolute extremum: 0, 0, "None"
    sharedPeak = max(origPeak, outPeak)
    if sharedPeak < 0.001
        sharedPeak = 0.001
    endif
    sharedAmp = 1.15 * sharedPeak

    # ----------------------------------------------------------
    # TITLE / SUBTITLE
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Delay Array##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -1.30, "half", "Delay Array.praat  |  " + displayName$ + "  |  repeated FIR delay differences"

    # ----------------------------------------------------------
    # SOURCE
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.65, 1.90
    Select inner viewport: 0.55, 7.75, 0.82, 1.78
    Axes: 0, duration, -sharedAmp, sharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, -sharedAmp, sharedAmp
    selectObject: vizOrig
    Colour: "{0.58, 0.58, 0.62}"
    Draw: 0, duration, -sharedAmp, sharedAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "##Source##"
    Font size: 6
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"
    Axes: 0, duration, -sharedAmp, sharedAmp
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.01 * duration, "left", 0.82 * sharedAmp, "half", "duration " + fixed$(duration, 3) + " s  |  " + string$(sampleRate) + " Hz"

    # ----------------------------------------------------------
    # DELAY CASCADE MAP
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 2.05, 4.55
    Select inner viewport: 0.55, 7.75, 2.22, 4.40
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "##Delay cascade map##"

    # One stage box per active iteration.  The box itself is the repeated
    # x[n+D] - x[n] operator; its label reports the actual D and 1/D spacing.
    stageW = 0.20
    stageGap = 0.025
    totalStageW = number_of_iterations * stageW + (number_of_iterations - 1) * stageGap
    stageStart = (1 - totalStageW) / 2
    stageY1 = 0.30
    stageY2 = 0.76

    # Input/output flow line behind the blocks.
    Colour: "{0.68, 0.68, 0.70}"
    Line width: 1.2
    Draw line: 0.025, 0.53, 0.975, 0.53
    Line width: 1

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.83, "half", "Each stage:  y[n] = x[n+D] - x[n]   |   zero-padded finite-signal boundary"

    for k to number_of_iterations
        x1 = stageStart + (k - 1) * (stageW + stageGap)
        x2 = x1 + stageW
        xc = (x1 + x2) / 2

        # light operation block; orange has one meaning here: FIR difference stage
        Paint rectangle: "{0.98, 0.94, 0.88}", x1, x2, stageY1, stageY2
        Colour: "{0.80, 0.47, 0.20}"
        Line width: 1.2
        Draw rectangle: x1, x2, stageY1, stageY2
        Line width: 1

        delaySamples = delayArr[k]
        delayMs = delaySamples / sampleRate * 1000
        combSpacing = sampleRate / delaySamples

        Font size: 6
        Colour: "Black"
        Text: xc, "centre", 0.70, "half", "##Stage " + string$(k) + "##"
        Font size: 5
        Colour: "{0.38, 0.28, 0.20}"
        Text: xc, "centre", 0.57, "half", "x[n+D] - x[n]"

        if use_ms_delay
            delayText$ = "D " + fixed$(delayMs, 3) + " ms"
        else
            delayText$ = "D " + fixed$(delayMs, 2) + " ms  (1/" + fixed$(divisor[k], 2) + " file)"
        endif
        Text: xc, "centre", 0.45, "half", delayText$
        Text: xc, "centre", 0.35, "half", "zero spacing " + fixed$(combSpacing, 2) + " Hz"

        # two-tap glyph: direct sample (-) and delayed/future sample (+)
        tapY = 0.23
        tapL = xc - 0.035
        tapR = xc + 0.035
        Colour: "{0.72, 0.72, 0.74}"
        Draw line: tapL, tapY, tapR, tapY
        Paint circle (mm): "{0.58, 0.58, 0.62}", tapL, tapY, 0.9
        Paint circle (mm): "{0.80, 0.47, 0.20}", tapR, tapY, 0.9
        Font size: 5
        Colour: "{0.28, 0.28, 0.28}"
        Text: tapL, "centre", 0.16, "half", "-x[n]"
        Text: tapR, "centre", 0.16, "half", "+x[n+D]"
    endfor

    Font size: 6
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.02, "left", 0.06, "half", presetName$ + "  |  " + delayMode$ + "  |  " + string$(number_of_iterations) + " iterations"

    # ----------------------------------------------------------
    # OUTPUT
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.70, 5.95
    Select inner viewport: 0.55, 7.75, 4.87, 5.83
    Axes: 0, duration, -sharedAmp, sharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, -sharedAmp, sharedAmp
    selectObject: vizResult
    Colour: "{0.25, 0.50, 0.82}"
    Draw: 0, duration, -sharedAmp, sharedAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "yes", "##Output##"
    Font size: 6
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"
    Axes: 0, duration, -sharedAmp, sharedAmp
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.01 * duration, "left", 0.82 * sharedAmp, "half", "peak-scaled to " + fixed$(scale_peak, 2) + "  |  " + string$(number_of_iterations) + " cascaded FIR differences"

    # ----------------------------------------------------------
    # SUMMARY
    # ----------------------------------------------------------
    minDelayMs = delayArr[1] / sampleRate * 1000
    maxDelayMs = minDelayMs
    minSpacing = sampleRate / delayArr[1]
    maxSpacing = minSpacing
    for k to number_of_iterations
        thisDelayMs = delayArr[k] / sampleRate * 1000
        thisSpacing = sampleRate / delayArr[k]
        if thisDelayMs < minDelayMs
            minDelayMs = thisDelayMs
        endif
        if thisDelayMs > maxDelayMs
            maxDelayMs = thisDelayMs
        endif
        if thisSpacing < minSpacing
            minSpacing = thisSpacing
        endif
        if thisSpacing > maxSpacing
            maxSpacing = thisSpacing
        endif
    endfor

    Select outer viewport: 0, 8, 6.10, 7.05
    Select inner viewport: 0.30, 7.80, 6.17, 6.98
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "{0.48, 0.48, 0.48}"
    Draw rectangle: 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.80, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.49, "half", presetName$ + "  |  mode " + delayMode$ + "  |  " + string$(number_of_iterations) + " iterations  |  delay range " + fixed$(minDelayMs, 3) + "-" + fixed$(maxDelayMs, 3) + " ms"
    Text: 0.02, "left", 0.18, "half", "Comb-zero spacing " + fixed$(minSpacing, 2) + "-" + fixed$(maxSpacing, 2) + " Hz  |  source/output duration " + fixed$(duration, 3) + " s  |  scale peak " + fixed$(scale_peak, 2)

    Font size: 10
    Colour: "Black"
    Line width: 1

    removeObject: vizOrig, vizResult
    selectObject: result
endif

# === Reselect result after visualization ===
selectObject: result

# === Final Info ===
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result