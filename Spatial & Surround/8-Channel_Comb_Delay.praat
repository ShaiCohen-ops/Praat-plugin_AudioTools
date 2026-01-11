# ============================================================
# Praat AudioTools - 8-Channel_Comb_Delay.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   8-Channel Comb Filter / Delay Processor
#   Creates 8 channels with different comb-filter settings.
#   Optional: Reverse even-numbered channels for spatial effects.
#
# Changelog v0.2:
#   - Merged 8-Channel_Delay and Odd_forward_Even_reversed
#   - Added presets
#   - Added reverse_even option
#   - Added visualization
# ============================================================

form 8-Channel Comb Delay
    comment === PRESETS ===
    optionmenu Preset: 1
        option: "Custom (use values below)"
        option: "Linear (2,4,6,8,10,12,14,16)"
        option: "Exponential (2,4,8,16,32,64,128,256)"
        option: "Fibonacci (2,3,5,8,13,21,34,55)"
        option: "Prime Numbers (2,3,5,7,11,13,17,19)"
        option: "Octaves (2,4,8,16,2,4,8,16)"
        option: "Dense Cluster (2,3,4,5,6,7,8,9)"
        option: "Wide Spread (2,8,18,32,50,72,98,128)"
        option: "Alternating (2,16,4,14,6,12,8,10)"
        option: "Reverse (24,20,16,12,10,8,4,2)"
    
    comment === Comb filter divisors (higher = shorter delay) ===
    positive Delay_1 2
    positive Delay_2 4
    positive Delay_3 8
    positive Delay_4 10
    positive Delay_5 12
    positive Delay_6 16
    positive Delay_7 20
    positive Delay_8 24
    
    comment === Processing options ===
    boolean Reverse_even_channels 0
    real Scale_peak 0.99
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Linear
    delay_1 = 2
    delay_2 = 4
    delay_3 = 6
    delay_4 = 8
    delay_5 = 10
    delay_6 = 12
    delay_7 = 14
    delay_8 = 16
    presetName$ = "Linear"
elsif preset = 3
    # Exponential
    delay_1 = 2
    delay_2 = 4
    delay_3 = 8
    delay_4 = 16
    delay_5 = 32
    delay_6 = 64
    delay_7 = 128
    delay_8 = 256
    presetName$ = "Exponential"
elsif preset = 4
    # Fibonacci
    delay_1 = 2
    delay_2 = 3
    delay_3 = 5
    delay_4 = 8
    delay_5 = 13
    delay_6 = 21
    delay_7 = 34
    delay_8 = 55
    presetName$ = "Fibonacci"
elsif preset = 5
    # Prime Numbers
    delay_1 = 2
    delay_2 = 3
    delay_3 = 5
    delay_4 = 7
    delay_5 = 11
    delay_6 = 13
    delay_7 = 17
    delay_8 = 19
    presetName$ = "Primes"
elsif preset = 6
    # Octaves
    delay_1 = 2
    delay_2 = 4
    delay_3 = 8
    delay_4 = 16
    delay_5 = 2
    delay_6 = 4
    delay_7 = 8
    delay_8 = 16
    presetName$ = "Octaves"
elsif preset = 7
    # Dense Cluster
    delay_1 = 2
    delay_2 = 3
    delay_3 = 4
    delay_4 = 5
    delay_5 = 6
    delay_6 = 7
    delay_7 = 8
    delay_8 = 9
    presetName$ = "Dense"
elsif preset = 8
    # Wide Spread
    delay_1 = 2
    delay_2 = 8
    delay_3 = 18
    delay_4 = 32
    delay_5 = 50
    delay_6 = 72
    delay_7 = 98
    delay_8 = 128
    presetName$ = "Wide"
elsif preset = 9
    # Alternating
    delay_1 = 2
    delay_2 = 16
    delay_3 = 4
    delay_4 = 14
    delay_5 = 6
    delay_6 = 12
    delay_7 = 8
    delay_8 = 10
    presetName$ = "Alternating"
elsif preset = 10
    # Reverse
    delay_1 = 24
    delay_2 = 20
    delay_3 = 16
    delay_4 = 12
    delay_5 = 10
    delay_6 = 8
    delay_7 = 4
    delay_8 = 2
    presetName$ = "Reverse"
else
    presetName$ = "Custom"
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

selectObject: originalID
originalDur = Get total duration
sr = Get sampling frequency

# === Ensure mono ===
nch = Get number of channels
if nch > 1
    Convert to mono
    monoID = selected("Sound")
else
    selectObject: originalID
    Copy: "mono_copy"
    monoID = selected("Sound")
endif

selectObject: monoID
Rename: "soundObj"
numSamples = Get number of samples

# === Store delay divisors ===
divisor[1] = delay_1
divisor[2] = delay_2
divisor[3] = delay_3
divisor[4] = delay_4
divisor[5] = delay_5
divisor[6] = delay_6
divisor[7] = delay_7
divisor[8] = delay_8

# === Create 8 channels with comb filter ===
for i from 1 to 8
    selectObject: monoID
    Copy: "Ch" + string$(i)
    ch[i] = selected("Sound")
    
    n = divisor[i]
    b = floor(numSamples / n)
    b_[i] = b
    
    Formula: "if col + 'b' <= ncol then self[col + 'b'] - self[col] else -self[col] fi"
endfor

# === Optionally reverse even-numbered channels ===
if reverse_even_channels
    for i from 1 to 8
        if i mod 2 = 0
            selectObject: ch[i]
            Reverse
        endif
    endfor
    revLabel$ = " (even reversed)"
else
    revLabel$ = ""
endif

# === Combine all 8 channels ===
selectObject: ch[1], ch[2], ch[3], ch[4], ch[5], ch[6], ch[7], ch[8]
Combine to stereo
result = selected("Sound")
Scale peak: scale_peak
Rename: originalName$ + "_8chComb_" + presetName$

# === Info ===
writeInfoLine: "=== 8-Channel Comb Delay ==="
appendInfoLine: "Source: ", originalName$
appendInfoLine: "Preset: ", presetName$, revLabel$
appendInfoLine: "Samples: ", numSamples
appendInfoLine: ""
appendInfoLine: "Channel settings (b = samples/divisor):"
for i from 1 to 8
    if reverse_even_channels and (i mod 2 = 0)
        dir$ = "REVERSED"
    else
        dir$ = "forward"
    endif
    appendInfoLine: "  Ch", i, ": /", divisor[i], " -> b=", b_[i], " (", dir$, ")"
endfor

# === Cleanup ===
removeObject: monoID
for i from 1 to 8
    removeObject: ch[i]
endfor

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 10, 0, 0.6
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "8-Ch Comb Delay: " + presetName$ + revLabel$ + " | " + originalName$
    
    # Channel diagram
    Select outer viewport: 0.5, 9.5, 0.8, 4.5
    Select inner viewport: 1.0, 9.0, 1.2, 4.2
    
    Axes: 0, 10, 0, 9
    
    # Background
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 10, 0, 9
    
    # Find max b for scaling bars
    maxB = b_[1]
    for i from 2 to 8
        if b_[i] > maxB
            maxB = b_[i]
        endif
    endfor
    
    # Draw each channel as bar with length proportional to b
    for i from 1 to 8
        yPos = 9 - i
        barLen = 8 * (b_[i] / maxB)
        if barLen < 0.5
            barLen = 0.5
        endif
        
        if reverse_even_channels and (i mod 2 = 0)
            # Even = reversed (reddish)
            Paint rectangle: "{0.85, 0.65, 0.65}", 0.5, 0.5 + barLen, yPos + 0.15, yPos + 0.75
            arrowDir$ = "<"
        else
            # Forward (bluish)
            Paint rectangle: "{0.65, 0.7, 0.85}", 0.5, 0.5 + barLen, yPos + 0.15, yPos + 0.75
            arrowDir$ = ">"
        endif
        
        Colour: "Black"
        Line width: 1
        Draw rectangle: 0.5, 0.5 + barLen, yPos + 0.15, yPos + 0.75
        
        Font size: 7
        Text: 0.6, "left", yPos + 0.45, "half", arrowDir$ + " Ch" + string$(i)
        Text: 0.5 + barLen + 0.1, "left", yPos + 0.45, "half", "/" + string$(divisor[i]) + " (b=" + string$(b_[i]) + ")"
    endfor
    
    # Legend
    Font size: 7
    Colour: "Black"
    Paint rectangle: "{0.65, 0.7, 0.85}", 0.5, 1.0, 0.15, 0.45
    Draw rectangle: 0.5, 1.0, 0.15, 0.45
    Text: 1.1, "left", 0.3, "half", "Forward"
    
    if reverse_even_channels
        Paint rectangle: "{0.85, 0.65, 0.65}", 5.0, 5.5, 0.15, 0.45
        Draw rectangle: 5.0, 5.5, 0.15, 0.45
        Text: 5.6, "left", 0.3, "half", "Even = Reversed"
    endif
    
    Colour: "Black"
    Draw inner box
    
    # Output waveform
    Select outer viewport: 0.5, 9.5, 4.7, 6.5
    Select inner viewport: 1.0, 9.0, 4.9, 6.3
    selectObject: result
    Colour: "{0.4, 0.5, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Output (8ch)"
    
    Font size: 10
    Colour: "Black"
endif

# === Done ===
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Output: 8-channel sound"

if play_result
    selectObject: result
    Play
endif

selectObject: result