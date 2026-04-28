# ============================================================
# Praat AudioTools - 8-channel_I_Ching.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   8-channel I Ching: Form & Speed
#   Uses I Ching hexagrams to generate algorithmic audio variations.
#   Each channel gets a unique hexagram that determines:
#   - Slice reversals (Yin lines = reversed)
#   - Speed deviation (hexagram value 0-63 maps to speed)
#
# Changelog v0.3:
#   - Resized visualization from 12x8 to 8x8 to match suite standard
#   - Replaced single-panel layout with multi-panel layout:
#       Panel A: Hexagram grid (8 channels)
#       Panel B: Speed factor bar chart
#       Panel C: Yin/Yang balance per channel
#       Panel D: Summary bar
#   - Added Cage-inspired ideas (see form options):
#       * Silence threshold: channels below threshold stay silent
#         (homage to 4'33")
#       * Time bracket mode: slice boundaries are inexact ranges
#         rather than fixed divisions (from Cage's time brackets)
#       * Indeterminate pitch: optional pitch inversion on Yin lines
#         (inspired by prepared piano unpredictability)
#       * Number of slices: variable (not fixed at 6) chosen by
#         second random throw (from Cage's use of the I Ching for
#         structural as well as micro-level decisions)
# ============================================================

form 8-channel I Ching Form & Speed
    comment === PRESETS ===
    optionmenu Preset: 1
        option: "Custom (use values below)"
        option: "Subtle (5% deviation)"
        option: "Moderate (20% deviation)"
        option: "Extreme (50% deviation)"
        option: "Chaos (100% deviation)"
        option: "Slow Drift (20% slower bias)"
        option: "Fast Drift (20% faster bias)"
        option: "Micro-variations (2% deviation)"

    comment === I Ching Configuration ===
    real Deviation_range 0.20
    real Speed_bias 0.0

    comment === Random seed (0 = truly random) ===
    integer Random_seed 0

    comment === Audio Settings ===
    positive Min_pitch 75
    positive Max_pitch 600
    boolean Override_sampling_frequency 1
    positive Target_sampling_frequency 44100

    comment === Cage-inspired Options ===
    boolean Silence_threshold_4_33 0
    real Silence_threshold_level 0.05
    boolean Time_bracket_mode 0
    real Time_bracket_jitter 0.15
    boolean Indeterminate_pitch_inversion 0
    boolean Variable_slice_count 0

    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    deviation_range = 0.05
    speed_bias = 0.0
    presetName$ = "Subtle"
elsif preset = 3
    deviation_range = 0.20
    speed_bias = 0.0
    presetName$ = "Moderate"
elsif preset = 4
    deviation_range = 0.50
    speed_bias = 0.0
    presetName$ = "Extreme"
elsif preset = 5
    deviation_range = 1.00
    speed_bias = 0.0
    presetName$ = "Chaos"
elsif preset = 6
    deviation_range = 0.20
    speed_bias = -0.15
    presetName$ = "SlowDrift"
elsif preset = 7
    deviation_range = 0.20
    speed_bias = 0.15
    presetName$ = "FastDrift"
elsif preset = 8
    deviation_range = 0.02
    speed_bias = 0.0
    presetName$ = "Micro"
else
    presetName$ = "Custom"
endif

# === Setup ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

if random_seed > 0
    appendInfoLine: "Note: Random seed ", random_seed, " requested (for documentation purposes)"
endif

originalSound = selected("Sound")
originalName$ = selected$("Sound")
original_freq = Get sampling frequency
original_dur = Get total duration

# === Info ===
writeInfoLine: "=== 8-Channel I Ching: Form & Speed ==="
appendInfoLine: "Source: ", originalName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Deviation: +/-", fixed$(deviation_range * 100, 0), "%"
appendInfoLine: "Speed bias: ", fixed$(speed_bias * 100, 0), "%"
if time_bracket_mode
    appendInfoLine: "Time bracket jitter: ", fixed$(time_bracket_jitter * 100, 0), "%"
endif
if silence_threshold_4_33
    appendInfoLine: "4'33 silence gate: ", fixed$(silence_threshold_level, 3)
endif
appendInfoLine: ""

# === Store hexagram data ===
for ch from 1 to 8
    hexValue[ch] = 0
    speedFactor[ch] = 1.0
    yinCount[ch] = 0
    sliceCount[ch] = 6
endfor

# === MAIN LOOP (8 CHANNELS) ===
for ch from 1 to 8

    # 1. GENERATE HEXAGRAM
    line[1] = randomInteger(0, 1)
    line[2] = randomInteger(0, 1)
    line[3] = randomInteger(0, 1)
    line[4] = randomInteger(0, 1)
    line[5] = randomInteger(0, 1)
    line[6] = randomInteger(0, 1)

    hex_value = line[1] + (line[2]*2) + (line[3]*4) + (line[4]*8) + (line[5]*16) + (line[6]*32)
    normalized_hex = hex_value / 63
    speed_factor = 1.0 + speed_bias + ((normalized_hex * (deviation_range * 2)) - deviation_range)

    if speed_factor < 0.1
        speed_factor = 0.1
    endif

    hexValue[ch] = hex_value
    speedFactor[ch] = speed_factor

    # Count yin lines for visualization
    yinCount[ch] = 0
    for k from 1 to 6
        if line[k] = 0
            yinCount[ch] = yinCount[ch] + 1
        endif
    endfor

    # Cage: variable slice count (second hexagram throw)
    if variable_slice_count
        hex2 = randomInteger(0, 63)
        sliceCount[ch] = 4 + round((hex2 / 63) * 8)
        if sliceCount[ch] < 2
            sliceCount[ch] = 2
        endif
        if sliceCount[ch] > 12
            sliceCount[ch] = 12
        endif
    else
        sliceCount[ch] = 6
    endif

    # 2. SLICING & RECOMBINATION
    selectObject: originalSound
    nSlices = sliceCount[ch]
    validSliceCount = 0

    for s from 1 to nSlices
        startTime = (s - 1) * (original_dur / nSlices)
        endTime = s * (original_dur / nSlices)

        # Cage: time bracket jitter
        if time_bracket_mode
            jitterRange = (original_dur / nSlices) * time_bracket_jitter
            startTime = startTime + randomUniform(-jitterRange, jitterRange)
            endTime = endTime + randomUniform(-jitterRange, jitterRange)
            if startTime < 0
                startTime = 0
            endif
            if endTime > original_dur
                endTime = original_dur
            endif
            if startTime >= endTime
                endTime = startTime + 0.001
            endif
        endif

        if endTime > original_dur
            endTime = original_dur
        endif

        if endTime - startTime > 0.001
            selectObject: originalSound
            Extract part: startTime, endTime, "rectangular", 1.0, "no"
            currentSliceID = selected("Sound")

            # Use line index mod 6 (wraps if more than 6 slices)
            lineIdx = ((s - 1) mod 6) + 1

            if line[lineIdx] = 0
                Reverse

                # Cage: pitch inversion on Yin lines
                if indeterminate_pitch_inversion
                    selectObject: selected("Sound")
                    dur_sl = Get total duration
                    sr_sl = Get sampling frequency
                    Shift pitch (PSOLA): min_pitch, max_pitch, -0.5
                endif
            endif

            validSliceCount += 1
            sliceID[validSliceCount] = selected("Sound")
        endif
    endfor

    if validSliceCount > 0
        selectObject: sliceID[1]
        for k from 2 to validSliceCount
            plusObject: sliceID[k]
        endfor
        Concatenate
        recombinedSound = selected("Sound")
        for k from 1 to validSliceCount
            removeObject: sliceID[k]
        endfor
    else
        selectObject: originalSound
        Copy: "fallback"
        recombinedSound = selected("Sound")
    endif

    # 3. SPEED & FINALIZATION
    selectObject: recombinedSound
    nChans = Get number of channels
    if nChans > 1
        Convert to mono
        removeObject: recombinedSound
        recombinedSound = selected("Sound")
    endif

    # Cage: 4'33 silence gate — if channel hex is too quiet, replace with silence
    if silence_threshold_4_33
        selectObject: recombinedSound
        chanPeak = Get absolute extremum: 0, 0, "None"
        if chanPeak < silence_threshold_level
            dur_rc = Get total duration
            sr_rc = Get sampling frequency
            removeObject: recombinedSound
            Create Sound from formula: "silence_ch", 1, 0, dur_rc, sr_rc, "0"
            recombinedSound = selected("Sound")
        endif
    endif

    dur_current = Get total duration
    target_dur = dur_current / speed_factor

    Lengthen (overlap-add): min_pitch, max_pitch, target_dur/dur_current

    removeObject: recombinedSound
    speedSound = selected("Sound")

    if override_sampling_frequency
        Resample: target_sampling_frequency, 50
    else
        Resample: original_freq, 50
    endif

    removeObject: speedSound
    final_channels[ch] = selected("Sound")
    Rename: "Ch" + string$(ch)

endfor

# === COMBINE 8 CHANNELS ===
selectObject: final_channels[1]
for i from 2 to 8
    plusObject: final_channels[i]
endfor

Combine to stereo
Rename: originalName$ + "_8chIChing_" + presetName$
Scale peak: 0.95
finalID = selected("Sound")

for i from 1 to 8
    removeObject: final_channels[i]
endfor

# === Final Info ===
appendInfoLine: "Hexagram results:"
for ch from 1 to 8
    appendInfoLine: "  Ch", ch, ": Hex #", hexValue[ch], " -> ", fixed$(speedFactor[ch], 3), "x speed  (Yin: ", yinCount[ch], "/6)"
endfor
appendInfoLine: ""
appendInfoLine: "=== Done ==="

# ============================================================
# VISUALIZATION  (8 x 8 canvas — matches suite standard)
# ============================================================
if draw_visualization

    Erase all

    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##8-CHANNEL I CHING: Form & Speed##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... originalName$
        ... + "  |  Preset: " + presetName$
        ... + "  |  Dev: ±" + fixed$(deviation_range * 100, 0) + "%"
        ... + "  |  Bias: " + fixed$(speed_bias * 100, 0) + "%"

    # ----------------------------------------------------------
    # PANEL A: HEXAGRAM GRID  (left column)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.38, 4.00, 0.85, 4.50

    Axes: 0, 10, 0, 10
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 10, 0, 10

    for ch from 1 to 8

        # Regenerate lines from hexValue for display
        hv = hexValue[ch]
        dline[1] = hv mod 2
        dline[2] = (hv div 2) mod 2
        dline[3] = (hv div 4) mod 2
        dline[4] = (hv div 8) mod 2
        dline[5] = (hv div 16) mod 2
        dline[6] = (hv div 32) mod 2

        if ch <= 4
            xCenter = 1.25 + (ch-1)*2.3
            yBase = 5.8
        else
            xCenter = 1.25 + (ch-5)*2.3
            yBase = 1.8
        endif

        Font size: 6
        Colour: "Black"
        Text: xCenter, "centre", yBase - 0.5, "half", "Ch" + string$(ch) + " #" + string$(hexValue[ch])
        Font size: 5
        Text: xCenter, "centre", yBase - 0.95, "half", "(" + fixed$(speedFactor[ch], 2) + "x)"

        Line width: 3
        for k from 1 to 6
            lineY = yBase + (k-1)*0.45

            if dline[k] = 1
                Colour: "{0.25, 0.50, 0.72}"
                Draw line: xCenter-0.85, lineY, xCenter+0.85, lineY
            else
                Colour: "{0.72, 0.35, 0.30}"
                Draw line: xCenter-0.85, lineY, xCenter-0.18, lineY
                Draw line: xCenter+0.18, lineY, xCenter+0.85, lineY
            endif
        endfor
        Line width: 1
        Colour: "Black"
    endfor

    Draw inner box

    # ----------------------------------------------------------
    # PANEL B: SPEED FACTOR BARS  (right column, upper)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 3.00
    Select inner viewport: 4.52, 7.75, 0.85, 2.92

    Axes: 0, 1.5, 0.5, 8.5
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1.5, 0.5, 8.5

    # Reference line at 1.0 (no speed change)
    Colour: "{0.75, 0.75, 0.75}"
    Dotted line
    Draw line: 1.0, 0.5, 1.0, 8.5
    Solid line

    for ch from 1 to 8
        y = 9 - ch
        yLo = y - 0.38
        yHi = y + 0.38
        sf = speedFactor[ch]

        # Colour by faster/slower
        if sf > 1.0
            Paint rectangle: "{0.30, 0.58, 0.80}", 0, sf, yLo, yHi
        else
            Paint rectangle: "{0.80, 0.45, 0.25}", 0, sf, yLo, yHi
        endif

        Font size: 5
        Colour: "{0.30, 0.30, 0.30}"
        Text: -0.02, "right", y, "half", "Ch" + string$(ch)
        Text: 1.47, "right", y, "half", fixed$(sf, 2) + "x"
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Ch"
    Text bottom: "yes", "Speed factor  (blue = faster, orange = slower)"

    # ----------------------------------------------------------
    # PANEL C: YIN/YANG BALANCE  (right column, lower)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 3.05, 4.60
    Select inner viewport: 4.52, 7.75, 3.12, 4.52

    Axes: 0, 6, 0.5, 8.5
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 6, 0.5, 8.5

    for ch from 1 to 8
        y = 9 - ch
        yLo = y - 0.38
        yHi = y + 0.38
        yc = yinCount[ch]
        yangCount = 6 - yc

        # Paint Yin (red) portion
        Paint rectangle: "{0.72, 0.35, 0.30}", 0, yc, yLo, yHi
        # Paint Yang (blue) portion on top
        Paint rectangle: "{0.25, 0.50, 0.72}", yc, 6, yLo, yHi

        Font size: 5
        Colour: "{0.30, 0.30, 0.30}"
        Text: -0.15, "right", y, "half", "Ch" + string$(ch)

        # Yin count label
        if yc > 0
            Colour: "White"
            Text: yc/2, "centre", y, "half", string$(yc)
        endif
        # Yang count label
        if yangCount > 0
            Colour: "White"
            Text: yc + yangCount/2, "centre", y, "half", string$(yangCount)
        endif
    endfor

    Colour: "{0.80, 0.80, 0.80}"
    Dotted line
    Draw line: 3, 0.5, 3, 8.5
    Solid line

    Colour: "Black"
    Draw inner box
    Font size: 5
    Text left: "yes", "Ch"
    Text bottom: "yes", "Lines: Yin (red) | Yang (blue)"

    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8

    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Hexagram grid  (blue = Yang,  red = Yin)"
    Text: 6.10, "centre", 7.30, "half", "Speed factors (upper) & Yin/Yang balance (lower)"

    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM (full width)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.75
    Select inner viewport: 0.55, 7.72, 4.75, 5.68

    selectObject: finalID
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

    selectObject: finalID
    Extract one channel: 1
    vizL = selected("Sound")
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1
    Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
    removeObject: vizL

    selectObject: finalID
    Extract one channel: 2
    vizR = selected("Sound")
    Colour: "{0.82, 0.45, 0.25}"
    Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
    removeObject: vizR

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Output stereo mix  (blue = L,  orange = R)"
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
        ... + "  |  Dev: ±" + fixed$(deviation_range * 100, 0) + "%"
        ... + "  |  Bias: " + fixed$(speed_bias * 100, 0) + "%"
        ... + "  |  " + fixed$(original_dur, 2) + " s"

    cageFlags$ = ""
    if silence_threshold_4_33
        cageFlags$ = cageFlags$ + "  4'33-gate=" + fixed$(silence_threshold_level, 3)
    endif
    if time_bracket_mode
        cageFlags$ = cageFlags$ + "  TimeBracket±" + fixed$(time_bracket_jitter * 100, 0) + "%"
    endif
    if indeterminate_pitch_inversion
        cageFlags$ = cageFlags$ + "  PitchInv"
    endif
    if variable_slice_count
        cageFlags$ = cageFlags$ + "  VarSlices"
    endif
    if cageFlags$ = ""
        cageFlags$ = "  (no Cage extensions active)"
    endif

    Text: 0.02, "left", 0.28, "half",
        ... "Cage extensions:" + cageFlags$

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1

endif

# === Play ===
if play_result
    selectObject: finalID
    Play
endif

selectObject: finalID
