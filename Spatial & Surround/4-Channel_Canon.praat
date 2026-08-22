# ============================================================
# Praat AudioTools - 4-Channel_Canon.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.1 (2026)
# v0.4.1 (2026): RUNTIME-VERIFIED VISUAL LAYOUT - aligned physical X grid; safe axis-label gaps; DSP unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   4-Channel Canon Generator - creates a musical canon effect
#   with 4 pitch-shifted voices on separate channels.
#
# Changelog v0.4:
#   - Resized visualization from non-standard 10x canvas to 8x8
#     to match suite standard (22.2 Stem Renderer, 8-ch I Ching,
#     8-ch Movements)
#   - Multi-panel layout:
#       Panel A: Canon score diagram (voice entries over time)
#       Panel B: Pitch / semitone bar chart per voice
#       Panel C: Delay staircase diagram
#       Panel D: Output waveform strip
#       Panel E: Summary bar
# ============================================================

form 4-Channel Canon Settings
    comment === PRESETS ===
    optionmenu Preset: 1
        option: "Custom (use values below)"
        option: "Classic Canon (unison, staggered)"
        option: "Octave Stack"
        option: "Perfect Fifths"
        option: "Major Chord"
        option: "Minor Chord"
        option: "Cluster (close intervals)"
        option: "Wide Spread"
        option: "Accelerando Canon"
        option: "Reverse Canon"

    comment === Pitch shift (percent, + = higher, - = lower) ===
    real Shift_percent_1 0
    real Shift_percent_2 6.0
    real Shift_percent_3 12.0
    real Shift_percent_4 -5.5

    comment === Canon delays (seconds) ===
    real Delay_1 0.0
    real Delay_2 0.3
    real Delay_3 0.6
    real Delay_4 0.9

    comment === Settings ===
    positive Resample_frequency 44100
    real Fade_time 0.01

    comment === Output ===
    optionmenu Output_format: 1
        option: "4 channels (quadraphonic)"
        option: "2 stereo pairs"
        option: "Stereo mix (L: V1+V2, R: V3+V4)"
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    shift_percent_1 = 0
    shift_percent_2 = 0
    shift_percent_3 = 0
    shift_percent_4 = 0
    delay_1 = 0.0
    delay_2 = 0.5
    delay_3 = 1.0
    delay_4 = 1.5
    presetName$ = "Classic"
elsif preset = 3
    shift_percent_1 = 100 * (2^(12/12) - 1)
    shift_percent_2 = 0
    shift_percent_3 = 100 * (2^(-12/12) - 1)
    shift_percent_4 = 100 * (2^(-24/12) - 1)
    delay_1 = 0.0
    delay_2 = 0.2
    delay_3 = 0.4
    delay_4 = 0.6
    presetName$ = "Octaves"
elsif preset = 4
    shift_percent_1 = 0
    shift_percent_2 = 100 * (2^(7/12) - 1)
    shift_percent_3 = 100 * (2^(14/12) - 1)
    shift_percent_4 = 100 * (2^(21/12) - 1)
    delay_1 = 0.0
    delay_2 = 0.3
    delay_3 = 0.6
    delay_4 = 0.9
    presetName$ = "Fifths"
elsif preset = 5
    shift_percent_1 = 0
    shift_percent_2 = 100 * (2^(4/12) - 1)
    shift_percent_3 = 100 * (2^(7/12) - 1)
    shift_percent_4 = 100 * (2^(12/12) - 1)
    delay_1 = 0.0
    delay_2 = 0.25
    delay_3 = 0.5
    delay_4 = 0.75
    presetName$ = "Major"
elsif preset = 6
    shift_percent_1 = 0
    shift_percent_2 = 100 * (2^(3/12) - 1)
    shift_percent_3 = 100 * (2^(7/12) - 1)
    shift_percent_4 = 100 * (2^(12/12) - 1)
    delay_1 = 0.0
    delay_2 = 0.25
    delay_3 = 0.5
    delay_4 = 0.75
    presetName$ = "Minor"
elsif preset = 7
    shift_percent_1 = 0
    shift_percent_2 = 100 * (2^(1/12) - 1)
    shift_percent_3 = 100 * (2^(2/12) - 1)
    shift_percent_4 = 100 * (2^(3/12) - 1)
    delay_1 = 0.0
    delay_2 = 0.15
    delay_3 = 0.3
    delay_4 = 0.45
    presetName$ = "Cluster"
elsif preset = 8
    shift_percent_1 = 100 * (2^(-12/12) - 1)
    shift_percent_2 = 100 * (2^(-5/12) - 1)
    shift_percent_3 = 100 * (2^(7/12) - 1)
    shift_percent_4 = 100 * (2^(19/12) - 1)
    delay_1 = 0.0
    delay_2 = 0.4
    delay_3 = 0.8
    delay_4 = 1.2
    presetName$ = "Wide"
elsif preset = 9
    shift_percent_1 = 0
    shift_percent_2 = 0
    shift_percent_3 = 0
    shift_percent_4 = 0
    delay_1 = 0.0
    delay_2 = 0.8
    delay_3 = 1.2
    delay_4 = 1.4
    presetName$ = "Accel"
elsif preset = 10
    shift_percent_1 = 100 * (2^(12/12) - 1)
    shift_percent_2 = 100 * (2^(5/12) - 1)
    shift_percent_3 = 0
    shift_percent_4 = 100 * (2^(-7/12) - 1)
    delay_1 = 0.9
    delay_2 = 0.6
    delay_3 = 0.3
    delay_4 = 0.0
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

# === Create Base Mono ===
selectObject: originalID
Copy: "base_work"
baseWorkID = selected("Sound")
Convert to mono
monoID = selected("Sound")
Resample: resample_frequency, 50
Rename: "base_resampled"
baseDur = Get total duration

removeObject: baseWorkID, monoID

# === Calculate shift rates ===
shift_rate_1 = resample_frequency * (1 + (shift_percent_1/100))
shift_rate_2 = resample_frequency * (1 + (shift_percent_2/100))
shift_rate_3 = resample_frequency * (1 + (shift_percent_3/100))
shift_rate_4 = resample_frequency * (1 + (shift_percent_4/100))

# === Create 4 pitched versions ===
select Sound base_resampled
Copy: "v1_work"
v1_work = selected("Sound")
Override sampling frequency: shift_rate_1
Resample: resample_frequency, 50
Rename: "voice_1"
v1_dur = Get total duration
if fade_time > 0
    Fade in: 0, 0, fade_time, "yes"
    Fade out: 0, v1_dur, -fade_time, "yes"
endif
removeObject: v1_work

select Sound base_resampled
Copy: "v2_work"
v2_work = selected("Sound")
Override sampling frequency: shift_rate_2
Resample: resample_frequency, 50
Rename: "voice_2"
v2_dur = Get total duration
if fade_time > 0
    Fade in: 0, 0, fade_time, "yes"
    Fade out: 0, v2_dur, -fade_time, "yes"
endif
removeObject: v2_work

select Sound base_resampled
Copy: "v3_work"
v3_work = selected("Sound")
Override sampling frequency: shift_rate_3
Resample: resample_frequency, 50
Rename: "voice_3"
v3_dur = Get total duration
if fade_time > 0
    Fade in: 0, 0, fade_time, "yes"
    Fade out: 0, v3_dur, -fade_time, "yes"
endif
removeObject: v3_work

select Sound base_resampled
Copy: "v4_work"
v4_work = selected("Sound")
Override sampling frequency: shift_rate_4
Resample: resample_frequency, 50
Rename: "voice_4"
v4_dur = Get total duration
if fade_time > 0
    Fade in: 0, 0, fade_time, "yes"
    Fade out: 0, v4_dur, -fade_time, "yes"
endif
removeObject: v4_work

# === Calculate output duration ===
end1 = delay_1 + v1_dur
end2 = delay_2 + v2_dur
end3 = delay_3 + v3_dur
end4 = delay_4 + v4_dur
maxEnd = max(end1, max(end2, max(end3, end4)))
outputDur = maxEnd + 0.05

# === Create 4 output channel buffers ===
Create Sound from formula: "ch1", 1, 0, outputDur, resample_frequency, "0"
ch1 = selected("Sound")
Create Sound from formula: "ch2", 1, 0, outputDur, resample_frequency, "0"
ch2 = selected("Sound")
Create Sound from formula: "ch3", 1, 0, outputDur, resample_frequency, "0"
ch3 = selected("Sound")
Create Sound from formula: "ch4", 1, 0, outputDur, resample_frequency, "0"
ch4 = selected("Sound")

# === Place each voice in its channel with delay ===
selectObject: ch1
Formula (part): delay_1, delay_1 + v1_dur, 1, 1, "Sound_voice_1(x - 'delay_1')"

selectObject: ch2
Formula (part): delay_2, delay_2 + v2_dur, 1, 1, "Sound_voice_2(x - 'delay_2')"

selectObject: ch3
Formula (part): delay_3, delay_3 + v3_dur, 1, 1, "Sound_voice_3(x - 'delay_3')"

selectObject: ch4
Formula (part): delay_4, delay_4 + v4_dur, 1, 1, "Sound_voice_4(x - 'delay_4')"

# === Combine based on output format ===
if output_format = 1
    selectObject: ch1, ch2
    Combine to stereo
    Rename: "pair_12"
    pair12 = selected("Sound")

    selectObject: ch3, ch4
    Combine to stereo
    Rename: "pair_34"
    pair34 = selected("Sound")

    selectObject: pair12, pair34
    Combine to stereo
    Scale peak: 0.95
    Rename: originalName$ + "_canon4ch_" + presetName$
    result = selected("Sound")

    removeObject: pair12, pair34
    formatName$ = "4-channel"

elsif output_format = 2
    selectObject: ch1, ch2
    Combine to stereo
    Scale peak: 0.95
    Rename: originalName$ + "_canon_pair1_" + presetName$
    result = selected("Sound")

    selectObject: ch3, ch4
    Combine to stereo
    Scale peak: 0.95
    Rename: originalName$ + "_canon_pair2_" + presetName$
    result2 = selected("Sound")

    formatName$ = "2 stereo pairs"

else
    selectObject: ch1
    Formula: "self + Sound_ch2(x)"
    Rename: "left_mix"
    leftMix = selected("Sound")

    selectObject: ch3
    Formula: "self + Sound_ch4(x)"
    Rename: "right_mix"
    rightMix = selected("Sound")

    selectObject: leftMix, rightMix
    Combine to stereo
    Scale peak: 0.95
    Rename: originalName$ + "_canon_stereo_" + presetName$
    result = selected("Sound")

    removeObject: leftMix, rightMix
    formatName$ = "stereo mix"
endif

# === Convert percent to semitones ===
semi1 = 12 * ln(1 + shift_percent_1/100) / ln(2)
semi2 = 12 * ln(1 + shift_percent_2/100) / ln(2)
semi3 = 12 * ln(1 + shift_percent_3/100) / ln(2)
semi4 = 12 * ln(1 + shift_percent_4/100) / ln(2)

# === Info ===
writeInfoLine: "=== 4-Channel Canon ==="
appendInfoLine: "Source: ", originalName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Output: ", formatName$
appendInfoLine: ""
appendInfoLine: "Voice 1 (Ch1): ", fixed$(semi1, 1), " st, delay ", fixed$(delay_1, 2), "s"
appendInfoLine: "Voice 2 (Ch2): ", fixed$(semi2, 1), " st, delay ", fixed$(delay_2, 2), "s"
appendInfoLine: "Voice 3 (Ch3): ", fixed$(semi3, 1), " st, delay ", fixed$(delay_3, 2), "s"
appendInfoLine: "Voice 4 (Ch4): ", fixed$(semi4, 1), " st, delay ", fixed$(delay_4, 2), "s"

# === Cleanup ===
select Sound base_resampled
plus Sound voice_1
plus Sound voice_2
plus Sound voice_3
plus Sound voice_4
Remove

if output_format <> 3
    selectObject: ch1, ch2, ch3, ch4
    Remove
endif

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================

if draw_visualization

    Erase all

    # Voice colours
    vColR[1] = 0.25
    vColG[1] = 0.50
    vColB[1] = 0.80
    vColR[2] = 0.30
    vColG[2] = 0.68
    vColB[2] = 0.30
    vColR[3] = 0.82
    vColG[3] = 0.55
    vColB[3] = 0.22
    vColR[4] = 0.72
    vColG[4] = 0.32
    vColB[4] = 0.55

    delay[1] = delay_1
    delay[2] = delay_2
    delay[3] = delay_3
    delay[4] = delay_4
    vDur[1] = v1_dur
    vDur[2] = v2_dur
    vDur[3] = v3_dur
    vDur[4] = v4_dur
    semi[1] = semi1
    semi[2] = semi2
    semi[3] = semi3
    semi[4] = semi4

    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##4-CHANNEL CANON v0.4.1##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... originalName$
        ... + "  |  Preset: " + presetName$
        ... + "  |  Format: " + formatName$
        ... + "  |  " + fixed$(outputDur, 2) + " s"

    # ----------------------------------------------------------
    # PANEL A: CANON SCORE DIAGRAM  (left column)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.15, 0.85, 4.75
    Select inner viewport: 0.60, 3.85, 0.95, 4.55

    Axes: 0, outputDur, 0, 5
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, outputDur, 0, 5

    # Vertical grid lines every 0.5s
    Colour: "{0.88, 0.88, 0.88}"
    Line width: 1
    tGrid = 0
    while tGrid <= outputDur
        Draw line: tGrid, 0, tGrid, 5
        tGrid = tGrid + 0.5
    endwhile

    for v from 1 to 4
        yLo = (4 - v) * 1.0 + 0.12
        yHi = yLo + 0.76
        yMid = yLo + 0.38

        # Voice bar
        Paint rectangle: "{" + string$(vColR[v]) + ", " + string$(vColG[v]) + ", " + string$(vColB[v]) + "}", delay[v], delay[v] + vDur[v], yLo, yHi

        # Outline
        Colour: "{0.30, 0.30, 0.30}"
        Line width: 1
        Draw rectangle: delay[v], delay[v] + vDur[v], yLo, yHi

        # Label
        Font size: 6
        Colour: "White"
        if semi[v] >= 0
            semiStr$ = "+" + fixed$(semi[v], 1) + " st"
        else
            semiStr$ = fixed$(semi[v], 1) + " st"
        endif
        Text: delay[v] + 0.04, "left", yMid, "half", "V" + string$(v) + "  " + semiStr$

        # Delay tick
        Colour: "{0.25, 0.25, 0.25}"
        Line width: 2
        Draw line: delay[v], 0, delay[v], yLo
        Line width: 1
    endfor

    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, 0.5, "yes", "yes", "no"
    Font size: 6
    Text bottom: "yes", "Time (s)"
    Select outer viewport: 0.12, 0.52, 0.85, 4.75
    Select inner viewport: 0.12, 0.52, 0.87, 4.73
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Voice"
    Select outer viewport: 0, 4.15, 0.85, 4.75
    Select inner viewport: 0.60, 3.85, 0.95, 4.55
    Axes: 0, outputDur, 0, 5

    # ----------------------------------------------------------
    # PANEL B: SEMITONE BAR CHART  (right column, upper)
    # ----------------------------------------------------------
    Select outer viewport: 4.15, 8, 0.85, 2.70
    Select inner viewport: 4.45, 7.70, 0.95, 2.48

    # Find axis range
    semiMax = max(max(semi1, semi2), max(semi3, semi4))
    semiMin = min(min(semi1, semi2), min(semi3, semi4))
    if semiMax < 1
        semiMax = 1
    endif
    if semiMin > -1
        semiMin = -1
    endif
    semiPad = (semiMax - semiMin) * 0.15 + 0.5

    Axes: semiMin - semiPad, semiMax + semiPad, 0.5, 4.5
    Paint rectangle: "{0.96, 0.96, 0.96}", semiMin - semiPad, semiMax + semiPad, 0.5, 4.5

    # Zero line
    Colour: "{0.75, 0.75, 0.75}"
    Dotted line
    Draw line: 0, 0.5, 0, 4.5
    Solid line

    for v from 1 to 4
        y = 5 - v
        yLo = y - 0.38
        yHi = y + 0.38
        sv = semi[v]

        if sv >= 0
            Paint rectangle: "{" + string$(vColR[v]) + ", " + string$(vColG[v]) + ", " + string$(vColB[v]) + "}", 0, sv, yLo, yHi
        else
            Paint rectangle: "{" + string$(vColR[v]) + ", " + string$(vColG[v]) + ", " + string$(vColB[v]) + "}", sv, 0, yLo, yHi
        endif

        Font size: 6
        Colour: "{0.30, 0.30, 0.30}"
        Text: semiMin - semiPad + 0.2, "left", y, "half", "V" + string$(v)

        Colour: "White"
        if abs(sv) > 0.3
            Text: sv / 2, "centre", y, "half", fixed$(sv, 1)
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 6
    Select outer viewport: 4.05, 4.40, 0.85, 2.70
    Select inner viewport: 4.05, 4.40, 0.87, 2.68
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "V"
    Select outer viewport: 4.15, 8, 0.85, 2.70
    Select inner viewport: 4.45, 7.70, 0.95, 2.48
    Axes: semiMin - semiPad, semiMax + semiPad, 0.5, 4.5
    Text bottom: "yes", "Pitch shift (semitones)"

    # ----------------------------------------------------------
    # PANEL C: DELAY STAIRCASE  (right column, lower)
    # ----------------------------------------------------------
    Select outer viewport: 4.15, 8, 3.00, 4.75
    Select inner viewport: 4.45, 7.70, 3.10, 4.53

    maxDelay = max(max(delay_1, delay_2), max(delay_3, delay_4))
    if maxDelay < 0.1
        maxDelay = 0.1
    endif

    Axes: -0.05, maxDelay + 0.15, 0.5, 4.5
    Paint rectangle: "{0.96, 0.96, 0.96}", -0.05, maxDelay + 0.15, 0.5, 4.5

    for v from 1 to 4
        y = 5 - v
        yLo = y - 0.38
        yHi = y + 0.38
        dv = delay[v]

        Paint rectangle: "{" + string$(vColR[v]) + ", " + string$(vColG[v]) + ", " + string$(vColB[v]) + "}", 0, dv + 0.005, yLo, yHi

        Font size: 6
        Colour: "{0.30, 0.30, 0.30}"
        Text: -0.04, "left", y, "half", "V" + string$(v)

        Colour: "White"
        if dv > 0.05
            Text: dv / 2, "centre", y, "half", fixed$(dv, 2) + "s"
        else
            Colour: "{0.30, 0.30, 0.30}"
            Text: dv + 0.02, "left", y, "half", fixed$(dv, 2) + "s"
        endif
    endfor

    # Staircase outline
    Colour: "{0.55, 0.55, 0.55}"
    Line width: 1
    for v from 1 to 3
        y1 = 5 - v - 0.38
        y2 = 5 - (v+1) + 0.38
        Draw line: delay[v], y1, delay[v], y2
        Draw line: delay[v], y2, delay[v+1], y2
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 6
    Select outer viewport: 4.05, 4.40, 3.00, 4.75
    Select inner viewport: 4.05, 4.40, 3.02, 4.73
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "V"
    Select outer viewport: 4.15, 8, 3.00, 4.75
    Select inner viewport: 4.45, 7.70, 3.10, 4.53
    Axes: -0.05, maxDelay + 0.15, 0.5, 4.5
    Text bottom: "yes", "Entry delay (s)"

    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8

    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.20, "half", "Canon score  (voices staggered in time)"
    Text: 6.10, "centre", 7.20, "half", "Pitch (upper) & entry delays (lower)"

    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM (full width)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.02, 6.14
    Select inner viewport: 0.60, 7.70, 5.10, 5.92

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
    nResultCh = Get number of channels
    if nResultCh >= 1
        Extract one channel: 1
        vizCh1 = selected("Sound")
        Colour: "{0.25, 0.50, 0.82}"
        Line width: 1
        Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
        removeObject: vizCh1
    endif
    if nResultCh >= 2
        selectObject: result
        Extract one channel: 2
        vizCh2 = selected("Sound")
        Colour: "{0.82, 0.45, 0.25}"
        Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
        removeObject: vizCh2
    endif

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Output  (blue = Ch1/L,  orange = Ch2/R)"
    Select outer viewport: 0.12, 0.52, 5.02, 6.14
    Select inner viewport: 0.12, 0.52, 5.04, 6.12
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Amp"
    Select outer viewport: 0, 8, 5.02, 6.14
    Select inner viewport: 0.60, 7.70, 5.10, 5.92
    Axes: 0, outDurViz, -ampViz, ampViz
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR (full width, bottom)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.38, 7.16
    Select inner viewport: 0.60, 7.70, 6.44, 7.10
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.62, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + originalName$
        ... + "  |  " + formatName$
        ... + "  |  " + fixed$(outputDur, 2) + " s  @" + string$(resample_frequency) + " Hz"

    Text: 0.02, "left", 0.30, "half",
        ... "V1: " + fixed$(semi1, 1) + " st / " + fixed$(delay_1, 2) + "s"
        ... + "   V2: " + fixed$(semi2, 1) + " st / " + fixed$(delay_2, 2) + "s"
        ... + "   V3: " + fixed$(semi3, 1) + " st / " + fixed$(delay_3, 2) + "s"
        ... + "   V4: " + fixed$(semi4, 1) + " st / " + fixed$(delay_4, 2) + "s"
        ... + "   Fade: " + fixed$(fade_time, 3) + "s"

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Select outer viewport: 0, 8, 0, 7.26
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
    Font size: 10
    Colour: "Black"
    Line width: 1

endif

# === Done ===
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Output duration: ", fixed$(outputDur, 2), "s"

if play_result
    selectObject: result
    Play
endif

selectObject: result
