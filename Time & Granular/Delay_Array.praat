# ============================================================
# Praat AudioTools - Delay_Array.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
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

form Delay Array v0.4
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

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 1, 8, 0.2, 0.7
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Delay Array: " + original_name$
    
    # Original waveform
    Select outer viewport: 0, 8, 0.9, 2.3
    Select inner viewport: 0.6, 7.6, 1.0, 2.2
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Select outer viewport: 0.1, 8, 0.5, 2.8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 2.4, 3.8
    Select inner viewport: 0.6, 7.6, 2.5, 3.7
    selectObject: result
    Colour: "{0.2, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Result"
    Text bottom: "yes", "Time (s)"
    
    # Spectrum display ceiling
    maxSpecHz = min(5000, sampleRate / 2)

    # Original spectrum
    Select outer viewport: 0, 4, 4.0, 5.6
    Select inner viewport: 0.6, 3.8, 4.2, 5.5
    selectObject: original
    nch = Get number of channels
    if nch > 1
        specMono = Convert to mono
    else
        specMono = Copy: "specMono"
    endif
    To Spectrum: "yes"
    origSpectrum = selected("Spectrum")
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, maxSpecHz, 0, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "dB"
    Text bottom: "yes", "Original spectrum (Hz)"
    removeObject: origSpectrum, specMono
    
    # Result spectrum
    Select outer viewport: 4, 8, 4.0, 5.6
    Select inner viewport: 4.4, 7.6, 4.2, 5.5
    selectObject: result
    nch = Get number of channels
    if nch > 1
        resMono = Convert to mono
    else
        resMono = Copy: "resMono"
    endif
    To Spectrum: "yes"
    resSpectrum = selected("Spectrum")
    Colour: "{0.3, 0.6, 0.8}"
    Draw: 0, maxSpecHz, 0, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "dB"
    Text bottom: "yes", "Result spectrum (Hz)"
    removeObject: resSpectrum, resMono
    
    # Legend
    Select outer viewport: 0.5, 8, 5.7, 6.1
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.4, 0.4, 0.4}"
    if use_ms_delay
        delayList$ = fixed$(msVal[1], 2)
        for k from 2 to number_of_iterations
            delayList$ = delayList$ + ", " + fixed$(msVal[k], 2)
        endfor
        legendMode$ = "ms delays: " + delayList$
    else
        delayList$ = fixed$(divisor[1], 2)
        for k from 2 to number_of_iterations
            delayList$ = delayList$ + ", " + fixed$(divisor[k], 2)
        endfor
        legendMode$ = "Divisors: " + delayList$
    endif
    Text: 0.5, "centre", 0.5, "half", presetName$ + " | " + legendMode$ + " | Iterations: " + string$(number_of_iterations)
    
    Font size: 10
    Colour: "Black"
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