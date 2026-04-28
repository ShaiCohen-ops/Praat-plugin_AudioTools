# ============================================================
# Praat AudioTools - 8-Channel_Comb_Delay.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   8-Channel Comb Filter / Delay Processor
#   Creates 8 channels with different comb-filter settings.
#   Optional: Reverse even-numbered channels for spatial effects.
#
# Changelog v0.3:
#   - Resized visualization from non-standard 10x canvas to 8x8
#     to match suite standard
#   - Multi-panel layout:
#       Panel A: Delay divisor bar chart (b samples, proportional)
#       Panel B: Comb period in ms per channel
#       Panel C: Forward/reverse direction diagram
#       Panel D: Output waveform strip
#       Panel E: Summary bar
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
    revLabel$ = " (even rev.)"
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
appendInfoLine: "Channel settings:"
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
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================

if draw_visualization

    Erase all

    # Find max/min b for axis scaling
    maxB = b_[1]
    minB = b_[1]
    for i from 2 to 8
        if b_[i] > maxB
            maxB = b_[i]
        endif
        if b_[i] < minB
            minB = b_[i]
        endif
    endfor

    # Max divisor for panel B axis
    maxDiv = divisor[1]
    for i from 2 to 8
        if divisor[i] > maxDiv
            maxDiv = divisor[i]
        endif
    endfor

    # Per-channel colour: blue = forward, red = reversed
    for i from 1 to 8
        if reverse_even_channels and (i mod 2 = 0)
            chR[i] = 0.80
            chG[i] = 0.38
            chB[i] = 0.32
        else
            # Blue, shaded by divisor rank
            intensity = (divisor[i] - 1) / (maxDiv + 1)
            chR[i] = 0.22 + intensity * 0.10
            chG[i] = 0.42 + intensity * 0.08
            chB[i] = 0.78 + intensity * 0.18
            if chB[i] > 1
                chB[i] = 1
            endif
        endif
    endfor

    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##8-CHANNEL COMB DELAY##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... originalName$
        ... + "  |  Preset: " + presetName$ + revLabel$
        ... + "  |  " + fixed$(originalDur, 2) + " s"
        ... + "  |  " + string$(numSamples) + " samples"
        ... + "  |  @" + string$(sr) + " Hz"

    # ----------------------------------------------------------
    # PANEL A: DELAY SAMPLES BAR CHART  (left column)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.38, 4.00, 0.85, 4.50

    axMax = maxB * 1.12
    Axes: 0, axMax, 0.5, 8.5
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, axMax, 0.5, 8.5

    # Vertical grid lines
    Colour: "{0.88, 0.88, 0.88}"
    Line width: 1
    gStep = maxB / 4
    if gStep < 1
        gStep = 1
    endif
    gVal = gStep
    while gVal < axMax
        Draw line: gVal, 0.5, gVal, 8.5
        gVal = gVal + gStep
    endwhile

    for i from 1 to 8
        y = 9 - i
        yLo = y - 0.38
        yHi = y + 0.38

        Paint rectangle: "{" + string$(chR[i]) + ", " + string$(chG[i]) + ", " + string$(chB[i]) + "}", 0, b_[i], yLo, yHi
        Colour: "{0.30, 0.30, 0.30}"
        Line width: 1
        Draw rectangle: 0, b_[i], yLo, yHi

        Font size: 5
        Colour: "{0.30, 0.30, 0.30}"
        Text: -axMax * 0.02, "right", y, "half", "Ch" + string$(i)
        Colour: "White"
        if b_[i] > maxB * 0.12
            Text: b_[i] / 2, "centre", y, "half", string$(b_[i])
        endif
        Colour: "{0.30, 0.30, 0.30}"
        Text: b_[i] + axMax * 0.02, "left", y, "half", "/" + string$(divisor[i])
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Comb delay b (samples)"
    Text left: "yes", "Ch"

    # ----------------------------------------------------------
    # PANEL B: COMB PERIOD IN MS  (right column, upper)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 3.00
    Select inner viewport: 4.52, 7.75, 0.85, 2.92

    # b samples → ms = b / sr * 1000
    maxMs = (maxB / sr) * 1000 * 1.12
    if maxMs < 1
        maxMs = 1
    endif

    Axes: 0, maxMs, 0.5, 8.5
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, maxMs, 0.5, 8.5

    # Grid
    Colour: "{0.88, 0.88, 0.88}"
    msGrid = maxMs / 4
    if msGrid < 0.1
        msGrid = 0.1
    endif
    msVal = msGrid
    while msVal < maxMs
        Draw line: msVal, 0.5, msVal, 8.5
        msVal = msVal + msGrid
    endwhile

    for i from 1 to 8
        y = 9 - i
        yLo = y - 0.38
        yHi = y + 0.38
        ms = (b_[i] / sr) * 1000

        Paint rectangle: "{" + string$(chR[i]) + ", " + string$(chG[i]) + ", " + string$(chB[i]) + "}", 0, ms, yLo, yHi
        Colour: "{0.30, 0.30, 0.30}"
        Draw rectangle: 0, ms, yLo, yHi

        Font size: 5
        Colour: "{0.30, 0.30, 0.30}"
        Text: -maxMs * 0.02, "right", y, "half", "Ch" + string$(i)
        Colour: "White"
        if ms > maxMs * 0.12
            Text: ms / 2, "centre", y, "half", fixed$(ms, 1) + " ms"
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 5
    Text left: "yes", "Ch"
    Text bottom: "yes", "Comb period (ms)"

    # ----------------------------------------------------------
    # PANEL C: DIRECTION DIAGRAM  (right column, lower)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 3.05, 4.60
    Select inner viewport: 4.52, 7.75, 3.12, 4.52

    Axes: 0, 10, 0.5, 8.5
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 10, 0.5, 8.5

    for i from 1 to 8
        y = 9 - i
        yLo = y - 0.38
        yHi = y + 0.38
        yMid = y

        if reverse_even_channels and (i mod 2 = 0)
            # Reversed: draw arrow pointing left
            Paint rectangle: "{0.90, 0.72, 0.70}", 0.3, 9.7, yLo, yHi
            Colour: "{0.70, 0.25, 0.20}"
            Line width: 2
            Draw arrow: 8.5, yMid, 1.5, yMid
            Line width: 1
            Font size: 5
            Colour: "White"
            Text: 5.0, "centre", yMid, "half", "Ch" + string$(i) + "  REVERSED  /÷" + string$(divisor[i])
        else
            # Forward: draw arrow pointing right
            Paint rectangle: "{0.72, 0.80, 0.90}", 0.3, 9.7, yLo, yHi
            Colour: "{0.20, 0.35, 0.70}"
            Line width: 2
            Draw arrow: 1.5, yMid, 8.5, yMid
            Line width: 1
            Font size: 5
            Colour: "White"
            Text: 5.0, "centre", yMid, "half", "Ch" + string$(i) + "  forward  /÷" + string$(divisor[i])
        endif
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 5
    Text bottom: "yes", "Playback direction  (blue = forward,  red = reversed)"

    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8

    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Comb delay b (samples) & divisor"
    Text: 6.10, "centre", 7.30, "half", "Period ms (upper) & direction (lower)"

    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM (full width)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.75
    Select inner viewport: 0.55, 7.72, 4.75, 5.68

    selectObject: result
    outDurViz = Get total duration
    outPeak = Get absolute extremum: 0, 0, "None"
    if outPeak < 0.001
        outPeak = 0.001
    endif
    ampViz = outPeak * 1.15

    Axes: 0, outDurViz, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, outDurViz, -ampViz, ampViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, outDurViz, 0

    selectObject: result
    Extract one channel: 1
    vizCh1 = selected("Sound")
    Colour: "{0.25, 0.45, 0.78}"
    Line width: 1
    Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
    removeObject: vizCh1

    selectObject: result
    Extract one channel: 2
    vizCh2 = selected("Sound")
    Colour: "{0.82, 0.45, 0.25}"
    Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
    removeObject: vizCh2

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Output 8-ch mix  (blue = Ch1,  orange = Ch2)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR (full width, bottom)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.82, 6.58
    Select inner viewport: 0.55, 7.72, 5.88, 6.52
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##" + revLabel$
        ... + "  " + originalName$
        ... + "  |  " + fixed$(originalDur, 2) + " s"
        ... + "  |  " + string$(numSamples) + " smp"
        ... + "  |  @" + string$(sr) + " Hz"

    Text: 0.02, "left", 0.28, "half",
        ... "÷" + string$(divisor[1])
        ... + "  ÷" + string$(divisor[2])
        ... + "  ÷" + string$(divisor[3])
        ... + "  ÷" + string$(divisor[4])
        ... + "  ÷" + string$(divisor[5])
        ... + "  ÷" + string$(divisor[6])
        ... + "  ÷" + string$(divisor[7])
        ... + "  ÷" + string$(divisor[8])
        ... + "  [Ch1–Ch8]"

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1

endif

# === Done ===
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Output: 8-channel comb delay"

if play_result
    selectObject: result
    Play
endif

selectObject: result
