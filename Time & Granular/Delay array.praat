# ============================================================
# Praat AudioTools - Delay_Array.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Delay Array - creates comb filtering effects by iteratively
#   subtracting delayed versions of the signal. Each divisor
#   creates notches at frequencies related to sample_rate/delay.
#
# Effect:
#   output[n] = input[n + delay] - input[n]
#   This is a high-pass comb filter (cancels low frequencies)
#
# Multiple iterations create complex spectral interference patterns.
#
# Changelog v0.2:
#   - Modern syntax
#   - Added visualization
#   - Added play option
#   - Bounds checking
# ============================================================

form Delay Array
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
    
    comment === Output ===
    positive Scale_peak 0.99
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 1
    divisor_1 = 2
    divisor_2 = 4
    divisor_3 = 8
    divisor_4 = 10
elsif preset = 2
    divisor_1 = 2
    divisor_2 = 3
    divisor_3 = 5
    divisor_4 = 7
elsif preset = 3
    divisor_1 = 4
    divisor_2 = 8
    divisor_3 = 12
    divisor_4 = 16
elsif preset = 4
    divisor_1 = 2
    divisor_2 = 6
    divisor_3 = 12
    divisor_4 = 24
elsif preset = 5
    divisor_1 = 2
    divisor_2 = 4
    divisor_3 = 8
    divisor_4 = 16
elsif preset = 6
    divisor_1 = 2
    divisor_2 = 3
    divisor_3 = 5
    divisor_4 = 11
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

# Store divisors in array
divisor[1] = divisor_1
divisor[2] = divisor_2
divisor[3] = divisor_3
divisor[4] = divisor_4

# === Info ===
writeInfoLine: "=== Delay Array ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Samples: ", totalSamples
appendInfoLine: ""
appendInfoLine: "Iterations: ", number_of_iterations
appendInfoLine: ""
appendInfoLine: "Iter | Divisor | Delay (samples) | Delay (ms) | Notch freq"
appendInfoLine: "-----|---------|-----------------|------------|----------"

for k to number_of_iterations
    delaySamples = floor(totalSamples / divisor[k])
    delayMs = delaySamples / sampleRate * 1000
    notchFreq = sampleRate / delaySamples
    appendInfoLine: "  ", k, "  |    ", divisor[k], "    |      ", delaySamples, "       |   ", fixed$(delayMs, 1), "    |  ", fixed$(notchFreq, 1), " Hz"
endfor
appendInfoLine: ""

# === Copy Sound ===
selectObject: original
Copy: original_name$ + "_delayArray"
result = selected("Sound")

# === Apply Delay Differencing ===
appendInfoLine: "Processing..."

for k to number_of_iterations
    selectObject: result
    delaySamples = floor(totalSamples / divisor[k])
    
    # Apply formula with bounds check
    Formula: "if col + delaySamples <= ncol then self[col + delaySamples] - self[col] else 0 fi"
    
    appendInfoLine: "  Iteration ", k, " done"
endfor

# === Scale Peak ===
selectObject: result
Scale peak: scale_peak

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.2, 0.7
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
    
    # Original spectrum
    Select outer viewport: 0, 4, 4.0, 5.6
    Select inner viewport: 0.6, 3.8, 4.2, 5.5
    selectObject: original
    To Spectrum: "yes"
    origSpectrum = selected("Spectrum")
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 5000, 0, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "dB"
    Text bottom: "yes", "Original spectrum (Hz)"
    removeObject: origSpectrum
    
    # Result spectrum
    Select outer viewport: 4, 8, 4.0, 5.6
    Select inner viewport: 4.4, 7.6, 4.2, 5.5
    selectObject: result
    To Spectrum: "yes"
    resSpectrum = selected("Spectrum")
    Colour: "{0.3, 0.6, 0.8}"
    Draw: 0, 5000, 0, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "dB"
    Text bottom: "yes", "Result spectrum (Hz)"
    removeObject: resSpectrum
    
    # Legend
    Select outer viewport: 0, 8, 5.7, 6.1
    Font size: 8
    Colour: "{0.4, 0.4, 0.4}"
    divList$ = string$(divisor[1])
    for k from 2 to number_of_iterations
        divList$ = divList$ + ", " + string$(divisor[k])
    endfor
    Text: 0.5, "centre", 0.5, "half", "Divisors: " + divList$ + " | Iterations: " + string$(number_of_iterations)
    
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