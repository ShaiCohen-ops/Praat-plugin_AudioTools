# ============================================================
# Praat AudioTools - 8_Channels_Time_Polyphony.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Time Polyphony - 8 Channels
#   Creates 8 time-stretched copies using PSOLA and combines
#   them into an 8-channel output. Each voice drifts at a
#   different rate, creating rich polyphonic textures.
#
# Changelog v0.3:
#   - Resized visualization from non-standard 10x canvas to 8x8
#     to match suite standard (22.2 Stem Renderer, 8-ch I Ching,
#     8-ch Movements, 4-ch Canon)
#   - Multi-panel layout:
#       Panel A: Duration bars (colour-coded by speed)
#       Panel B: Time scale bar chart with ×1 reference
#       Panel C: Duration deviation from original
#       Panel D: Output waveform strip
#       Panel E: Summary bar
# ============================================================

form Time Polyphony - 8 Channels
    comment === PRESETS ===
    optionmenu Preset: 1
        option: "Custom (use values below)"
        option: "Classic Polyphony"
        option: "Slow Motion"
        option: "Fast Chaos"
        option: "Rhythmic Pulse"
        option: "Subtle Variation"
        option: "Extreme Stretch"
        option: "Glitch Matrix"
        option: "Converging"
        option: "Diverging"

    comment === Time scales (1.0 = normal, >1 = slower, <1 = faster) ===
    real Time_scale_1 1.0
    real Time_scale_2 1.15
    real Time_scale_3 0.85
    real Time_scale_4 1.3
    real Time_scale_5 0.7
    real Time_scale_6 1.1
    real Time_scale_7 0.9
    real Time_scale_8 1.2

    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    time_scale_1 = 1.0
    time_scale_2 = 1.15
    time_scale_3 = 0.85
    time_scale_4 = 1.3
    time_scale_5 = 0.7
    time_scale_6 = 1.1
    time_scale_7 = 0.9
    time_scale_8 = 1.2
    presetName$ = "Classic"
elsif preset = 3
    time_scale_1 = 1.5
    time_scale_2 = 1.7
    time_scale_3 = 1.3
    time_scale_4 = 1.6
    time_scale_5 = 1.4
    time_scale_6 = 1.8
    time_scale_7 = 1.2
    time_scale_8 = 1.9
    presetName$ = "SlowMo"
elsif preset = 4
    time_scale_1 = 0.5
    time_scale_2 = 0.6
    time_scale_3 = 0.4
    time_scale_4 = 0.7
    time_scale_5 = 0.3
    time_scale_6 = 0.8
    time_scale_7 = 0.25
    time_scale_8 = 0.9
    presetName$ = "FastChaos"
elsif preset = 5
    time_scale_1 = 1.0
    time_scale_2 = 0.5
    time_scale_3 = 1.0
    time_scale_4 = 0.5
    time_scale_5 = 1.0
    time_scale_6 = 0.5
    time_scale_7 = 1.0
    time_scale_8 = 0.5
    presetName$ = "Rhythmic"
elsif preset = 6
    time_scale_1 = 1.0
    time_scale_2 = 1.05
    time_scale_3 = 0.98
    time_scale_4 = 1.02
    time_scale_5 = 0.95
    time_scale_6 = 1.03
    time_scale_7 = 0.97
    time_scale_8 = 1.01
    presetName$ = "Subtle"
elsif preset = 7
    time_scale_1 = 3.0
    time_scale_2 = 2.5
    time_scale_3 = 3.5
    time_scale_4 = 2.0
    time_scale_5 = 4.0
    time_scale_6 = 2.2
    time_scale_7 = 3.8
    time_scale_8 = 2.7
    presetName$ = "Extreme"
elsif preset = 8
    time_scale_1 = 0.15
    time_scale_2 = 0.8
    time_scale_3 = 0.3
    time_scale_4 = 1.5
    time_scale_5 = 0.2
    time_scale_6 = 1.2
    time_scale_7 = 0.4
    time_scale_8 = 2.0
    presetName$ = "Glitch"
elsif preset = 9
    time_scale_1 = 0.7
    time_scale_2 = 0.8
    time_scale_3 = 0.9
    time_scale_4 = 0.95
    time_scale_5 = 1.05
    time_scale_6 = 1.1
    time_scale_7 = 1.2
    time_scale_8 = 1.3
    presetName$ = "Converge"
elsif preset = 10
    time_scale_1 = 1.0
    time_scale_2 = 1.0
    time_scale_3 = 1.0
    time_scale_4 = 1.0
    time_scale_5 = 1.0
    time_scale_6 = 1.0
    time_scale_7 = 1.0
    time_scale_8 = 1.0
    presetName$ = "Diverge"
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

# === Store time scales in array ===
scale[1] = time_scale_1
scale[2] = time_scale_2
scale[3] = time_scale_3
scale[4] = time_scale_4
scale[5] = time_scale_5
scale[6] = time_scale_6
scale[7] = time_scale_7
scale[8] = time_scale_8

# === Info ===
writeInfoLine: "=== 8-Channel Time Polyphony ==="
appendInfoLine: "Source: ", originalName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Original duration: ", fixed$(originalDur, 2), "s"
appendInfoLine: ""
appendInfoLine: "Processing 8 voices with PSOLA..."

# === Create 8 time-stretched voices ===
for i from 1 to 8
    selectObject: originalID

    manip = To Manipulation: 0.01, 75, 600

    durTier = Create DurationTier: "dur", 0, originalDur
    Add point: 0, scale[i]
    Add point: originalDur, scale[i]

    selectObject: manip, durTier
    Replace duration tier

    selectObject: manip
    voice[i] = Get resynthesis (overlap-add)

    removeObject: durTier, manip

    selectObject: voice[i]
    dur[i] = Get total duration

    appendInfoLine: "  Ch", i, ": ×", fixed$(scale[i], 2), " → ", fixed$(dur[i], 2), "s"
endfor

# === Combine all 8 voices into 8-channel output ===
selectObject: voice[1], voice[2]
Combine to stereo
pair12 = selected("Sound")

selectObject: voice[3], voice[4]
Combine to stereo
pair34 = selected("Sound")

selectObject: voice[5], voice[6]
Combine to stereo
pair56 = selected("Sound")

selectObject: voice[7], voice[8]
Combine to stereo
pair78 = selected("Sound")

selectObject: pair12, pair34
Combine to stereo
quad1234 = selected("Sound")

selectObject: pair56, pair78
Combine to stereo
quad5678 = selected("Sound")

selectObject: quad1234, quad5678
Combine to stereo
result = selected("Sound")
Scale peak: 0.99
Rename: originalName$ + "_timePoly_" + presetName$

# === Cleanup ===
for i from 1 to 8
    removeObject: voice[i]
endfor
removeObject: pair12, pair34, pair56, pair78, quad1234, quad5678

selectObject: result
finalDur = Get total duration

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================

if draw_visualization

    Erase all

    # Compute per-channel colour: blue = slower (scale>=1), orange/red = faster (scale<1)
    for i from 1 to 8
        if scale[i] >= 1.0
            intensity = (scale[i] - 1.0) / 3.0
            if intensity > 1
                intensity = 1
            endif
            chR[i] = 0.25 + intensity * 0.10
            chG[i] = 0.45 + intensity * 0.05
            chB[i] = 0.78 + intensity * 0.18
        else
            intensity = (1.0 - scale[i]) / 0.85
            if intensity > 1
                intensity = 1
            endif
            chR[i] = 0.72 + intensity * 0.22
            chG[i] = 0.45 - intensity * 0.28
            chB[i] = 0.22 - intensity * 0.12
        endif
        if chR[i] > 1
            chR[i] = 1
        endif
        if chG[i] < 0
            chG[i] = 0
        endif
        if chB[i] < 0
            chB[i] = 0
        endif
    endfor

    # Max/min duration for axes
    maxDur = dur[1]
    minDur = dur[1]
    for i from 2 to 8
        if dur[i] > maxDur
            maxDur = dur[i]
        endif
        if dur[i] < minDur
            minDur = dur[i]
        endif
    endfor

    maxScale = scale[1]
    minScale = scale[1]
    for i from 2 to 8
        if scale[i] > maxScale
            maxScale = scale[i]
        endif
        if scale[i] < minScale
            minScale = scale[i]
        endif
    endfor

    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##8-CHANNEL TIME POLYPHONY##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... originalName$
        ... + "  |  Preset: " + presetName$
        ... + "  |  Orig: " + fixed$(originalDur, 2) + " s"
        ... + "  |  Output: " + fixed$(finalDur, 2) + " s"

    # ----------------------------------------------------------
    # PANEL A: DURATION BARS  (left column)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.38, 4.00, 0.85, 4.50

    axMax = maxDur * 1.08
    Axes: 0, axMax, 0.5, 8.5
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, axMax, 0.5, 8.5

    # Vertical grid lines
    Colour: "{0.88, 0.88, 0.88}"
    tGrid = 0
    while tGrid <= axMax
        Draw line: tGrid, 0.5, tGrid, 8.5
        tGrid = tGrid + originalDur / 4
    endwhile

    # Original duration marker
    Colour: "{0.75, 0.25, 0.25}"
    Line width: 2
    Dotted line
    Draw line: originalDur, 0.5, originalDur, 8.5
    Solid line
    Line width: 1
    Font size: 5
    Text: originalDur, "centre", 8.65, "half", "orig"

    for i from 1 to 8
        y = 9 - i
        yLo = y - 0.38
        yHi = y + 0.38

        Paint rectangle: "{" + string$(chR[i]) + ", " + string$(chG[i]) + ", " + string$(chB[i]) + "}", 0, dur[i], yLo, yHi

        Colour: "{0.30, 0.30, 0.30}"
        Line width: 1
        Draw rectangle: 0, dur[i], yLo, yHi

        Font size: 5
        Colour: "White"
        Text: dur[i] / 2, "centre", y, "half", "Ch" + string$(i) + "  ×" + fixed$(scale[i], 2)

        Colour: "{0.35, 0.35, 0.35}"
        Text: dur[i] + axMax * 0.02, "left", y, "half", fixed$(dur[i], 2) + "s"
    endfor

    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, originalDur / 2, "yes", "yes", "no"
    Font size: 6
    Text bottom: "yes", "Duration (s)  (red dashes = original)"
    Text left: "yes", "Ch"

    # ----------------------------------------------------------
    # PANEL B: TIME SCALE BARS  (right column, upper)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 3.00
    Select inner viewport: 4.52, 7.75, 0.85, 2.92

    scPad = (maxScale - minScale) * 0.12 + 0.05
    scLo = minScale - scPad
    scHi = maxScale + scPad
    if scLo > 0.85
        scLo = 0.85
    endif
    if scHi < 1.15
        scHi = 1.15
    endif

    Axes: scLo, scHi, 0.5, 8.5
    Paint rectangle: "{0.96, 0.96, 0.96}", scLo, scHi, 0.5, 8.5

    # ×1 reference line
    Colour: "{0.75, 0.75, 0.75}"
    Dotted line
    Draw line: 1.0, 0.5, 1.0, 8.5
    Solid line

    for i from 1 to 8
        y = 9 - i
        yLo = y - 0.38
        yHi = y + 0.38
        sv = scale[i]

        if sv >= 1.0
            Paint rectangle: "{" + string$(chR[i]) + ", " + string$(chG[i]) + ", " + string$(chB[i]) + "}", 1.0, sv, yLo, yHi
        else
            Paint rectangle: "{" + string$(chR[i]) + ", " + string$(chG[i]) + ", " + string$(chB[i]) + "}", sv, 1.0, yLo, yHi
        endif

        Font size: 5
        Colour: "{0.30, 0.30, 0.30}"
        Text: scLo + (scHi - scLo) * 0.02, "left", y, "half", "Ch" + string$(i)
        Colour: "White"
        if abs(sv - 1.0) > (scHi - scLo) * 0.06
            Text: (sv + 1.0) / 2, "centre", y, "half", "×" + fixed$(sv, 2)
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 5
    Text left: "yes", "Ch"
    Text bottom: "yes", "Time scale  (blue = slower,  orange = faster)"

    # ----------------------------------------------------------
    # PANEL C: DURATION DEVIATION FROM ORIGINAL  (right, lower)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 3.05, 4.60
    Select inner viewport: 4.52, 7.75, 3.12, 4.52

    # Deviation in seconds from original
    devMax = 0
    for i from 1 to 8
        d = abs(dur[i] - originalDur)
        if d > devMax
            devMax = d
        endif
    endfor
    if devMax < 0.01
        devMax = 0.01
    endif
    devPad = devMax * 0.15

    Axes: -(devMax + devPad), devMax + devPad, 0.5, 8.5
    Paint rectangle: "{0.96, 0.96, 0.96}", -(devMax + devPad), devMax + devPad, 0.5, 8.5

    # Zero line
    Colour: "{0.75, 0.75, 0.75}"
    Dotted line
    Draw line: 0, 0.5, 0, 8.5
    Solid line

    for i from 1 to 8
        y = 9 - i
        yLo = y - 0.38
        yHi = y + 0.38
        dev = dur[i] - originalDur

        if dev >= 0
            Paint rectangle: "{" + string$(chR[i]) + ", " + string$(chG[i]) + ", " + string$(chB[i]) + "}", 0, dev, yLo, yHi
        else
            Paint rectangle: "{" + string$(chR[i]) + ", " + string$(chG[i]) + ", " + string$(chB[i]) + "}", dev, 0, yLo, yHi
        endif

        Font size: 5
        Colour: "{0.30, 0.30, 0.30}"
        Text: -(devMax + devPad) * 0.98, "left", y, "half", "Ch" + string$(i)
        Colour: "White"
        if abs(dev) > devMax * 0.15
            Text: dev / 2, "centre", y, "half", fixed$(dev, 2) + "s"
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 5
    Text left: "yes", "Ch"
    Text bottom: "yes", "Deviation from original (s)"

    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8

    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Output duration per channel"
    Text: 6.10, "centre", 7.30, "half", "Time scale (upper) & deviation from original (lower)"

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
        ... "##" + presetName$ + "##"
        ... + "  " + originalName$
        ... + "  |  Orig: " + fixed$(originalDur, 2) + " s"
        ... + "  |  Output: " + fixed$(finalDur, 2) + " s"
        ... + "  |  @" + string$(sr) + " Hz"

    Text: 0.02, "left", 0.28, "half",
        ... "×" + fixed$(scale[1], 2)
        ... + "  ×" + fixed$(scale[2], 2)
        ... + "  ×" + fixed$(scale[3], 2)
        ... + "  ×" + fixed$(scale[4], 2)
        ... + "  ×" + fixed$(scale[5], 2)
        ... + "  ×" + fixed$(scale[6], 2)
        ... + "  ×" + fixed$(scale[7], 2)
        ... + "  ×" + fixed$(scale[8], 2)
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
appendInfoLine: "Output: 8-channel, ", fixed$(finalDur, 2), "s"

if play_result
    selectObject: result
    Play
endif

selectObject: result
