# ============================================================
# Praat AudioTools - 8-Channel_Canon.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   8-Channel Canon Generator - creates a musical canon effect
#   with 8 pitch-shifted voices on separate channels.
#
# Changelog v0.2:
#   - Added time delays for true canon effect
#   - Changed from Hz to semitones (more musical)
#   - Fixed cleanup
#   - Added visualization
#   - Refactored with loops
# ============================================================

form 8-Channel Canon Settings
    comment === PRESETS ===
    optionmenu Preset: 1
        option: "Custom (use values below)"
        option: "Classic Canon (unison, staggered)"
        option: "Cluster (1-3 semitones)"
        option: "Wide Spread (4-10 semitones)"
        option: "Microtonal (quarter-tones)"
        option: "Symmetrical (mirror intervals)"
        option: "Octave Stack"
        option: "Major Scale"
        option: "Chromatic"
        option: "Fifths Tower"
    
    comment === Pitch shifts (semitones) ===
    real Semitones_1 0
    real Semitones_2 2
    real Semitones_3 4
    real Semitones_4 5
    real Semitones_5 7
    real Semitones_6 9
    real Semitones_7 11
    real Semitones_8 12
    
    comment === Canon delays (seconds) ===
    real Delay_1 0.0
    real Delay_2 0.2
    real Delay_3 0.4
    real Delay_4 0.6
    real Delay_5 0.8
    real Delay_6 1.0
    real Delay_7 1.2
    real Delay_8 1.4
    
    comment === Settings ===
    positive Resample_frequency 44100
    real Fade_time 0.01
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Classic Canon (unison, staggered)
    semitones_1 = 0
    semitones_2 = 0
    semitones_3 = 0
    semitones_4 = 0
    semitones_5 = 0
    semitones_6 = 0
    semitones_7 = 0
    semitones_8 = 0
    delay_1 = 0.0
    delay_2 = 0.3
    delay_3 = 0.6
    delay_4 = 0.9
    delay_5 = 1.2
    delay_6 = 1.5
    delay_7 = 1.8
    delay_8 = 2.1
    presetName$ = "Classic"
elsif preset = 3
    # Cluster (1-3 semitones)
    semitones_1 = 0
    semitones_2 = 1
    semitones_3 = 2
    semitones_4 = 3
    semitones_5 = -1
    semitones_6 = -2
    semitones_7 = -3
    semitones_8 = -4
    delay_1 = 0.0
    delay_2 = 0.15
    delay_3 = 0.3
    delay_4 = 0.45
    delay_5 = 0.6
    delay_6 = 0.75
    delay_7 = 0.9
    delay_8 = 1.05
    presetName$ = "Cluster"
elsif preset = 4
    # Wide Spread
    semitones_1 = 0
    semitones_2 = 4
    semitones_3 = 7
    semitones_4 = 10
    semitones_5 = -3
    semitones_6 = -7
    semitones_7 = -10
    semitones_8 = -14
    delay_1 = 0.0
    delay_2 = 0.25
    delay_3 = 0.5
    delay_4 = 0.75
    delay_5 = 1.0
    delay_6 = 1.25
    delay_7 = 1.5
    delay_8 = 1.75
    presetName$ = "Wide"
elsif preset = 5
    # Microtonal (quarter-tones = 0.5 semitones)
    semitones_1 = 0
    semitones_2 = 0.5
    semitones_3 = 1.0
    semitones_4 = 1.5
    semitones_5 = 2.0
    semitones_6 = -0.5
    semitones_7 = -1.0
    semitones_8 = -1.5
    delay_1 = 0.0
    delay_2 = 0.1
    delay_3 = 0.2
    delay_4 = 0.3
    delay_5 = 0.4
    delay_6 = 0.5
    delay_7 = 0.6
    delay_8 = 0.7
    presetName$ = "Microtonal"
elsif preset = 6
    # Symmetrical (mirror intervals)
    semitones_1 = 6
    semitones_2 = 4
    semitones_3 = 2
    semitones_4 = 0
    semitones_5 = 0
    semitones_6 = -2
    semitones_7 = -4
    semitones_8 = -6
    delay_1 = 0.0
    delay_2 = 0.2
    delay_3 = 0.4
    delay_4 = 0.6
    delay_5 = 0.6
    delay_6 = 0.8
    delay_7 = 1.0
    delay_8 = 1.2
    presetName$ = "Symmetrical"
elsif preset = 7
    # Octave Stack
    semitones_1 = 0
    semitones_2 = 12
    semitones_3 = -12
    semitones_4 = 24
    semitones_5 = -24
    semitones_6 = 12
    semitones_7 = -12
    semitones_8 = 0
    delay_1 = 0.0
    delay_2 = 0.2
    delay_3 = 0.4
    delay_4 = 0.6
    delay_5 = 0.8
    delay_6 = 1.0
    delay_7 = 1.2
    delay_8 = 1.4
    presetName$ = "Octaves"
elsif preset = 8
    # Major Scale
    semitones_1 = 0
    semitones_2 = 2
    semitones_3 = 4
    semitones_4 = 5
    semitones_5 = 7
    semitones_6 = 9
    semitones_7 = 11
    semitones_8 = 12
    delay_1 = 0.0
    delay_2 = 0.15
    delay_3 = 0.3
    delay_4 = 0.45
    delay_5 = 0.6
    delay_6 = 0.75
    delay_7 = 0.9
    delay_8 = 1.05
    presetName$ = "MajorScale"
elsif preset = 9
    # Chromatic
    semitones_1 = 0
    semitones_2 = 1
    semitones_3 = 2
    semitones_4 = 3
    semitones_5 = 4
    semitones_6 = 5
    semitones_7 = 6
    semitones_8 = 7
    delay_1 = 0.0
    delay_2 = 0.1
    delay_3 = 0.2
    delay_4 = 0.3
    delay_5 = 0.4
    delay_6 = 0.5
    delay_7 = 0.6
    delay_8 = 0.7
    presetName$ = "Chromatic"
elsif preset = 10
    # Fifths Tower (stacked perfect fifths)
    semitones_1 = 0
    semitones_2 = 7
    semitones_3 = 14
    semitones_4 = 21
    semitones_5 = -7
    semitones_6 = -14
    semitones_7 = -21
    semitones_8 = -28
    delay_1 = 0.0
    delay_2 = 0.25
    delay_3 = 0.5
    delay_4 = 0.75
    delay_5 = 1.0
    delay_6 = 1.25
    delay_7 = 1.5
    delay_8 = 1.75
    presetName$ = "Fifths"
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

# === Store parameters in arrays ===
semi[1] = semitones_1
semi[2] = semitones_2
semi[3] = semitones_3
semi[4] = semitones_4
semi[5] = semitones_5
semi[6] = semitones_6
semi[7] = semitones_7
semi[8] = semitones_8

delay[1] = delay_1
delay[2] = delay_2
delay[3] = delay_3
delay[4] = delay_4
delay[5] = delay_5
delay[6] = delay_6
delay[7] = delay_7
delay[8] = delay_8

# === Create 8 pitched versions ===
for i from 1 to 8
    select Sound base_resampled
    Copy: "v" + string$(i) + "_work"
    vWork = selected("Sound")
    
    # Calculate shift rate from semitones
    ratio = 2 ^ (semi[i] / 12)
    shiftRate = resample_frequency * ratio
    
    Override sampling frequency: shiftRate
    Resample: resample_frequency, 50
    Rename: "voice_" + string$(i)
    voice[i] = selected("Sound")
    dur[i] = Get total duration
    
    if fade_time > 0
        Fade in: 0, 0, fade_time, "yes"
        Fade out: 0, dur[i], -fade_time, "yes"
    endif
    
    removeObject: vWork
endfor

# === Calculate output duration ===
maxEnd = 0
for i from 1 to 8
    thisEnd = delay[i] + dur[i]
    if thisEnd > maxEnd
        maxEnd = thisEnd
    endif
endfor
outputDur = maxEnd + 0.05

# === Create 8 output channel buffers ===
for i from 1 to 8
    Create Sound from formula: "ch" + string$(i), 1, 0, outputDur, resample_frequency, "0"
    ch[i] = selected("Sound")
endfor

# === Place each voice in its channel with delay ===
for i from 1 to 8
    selectObject: ch[i]
    d = delay[i]
    voiceDur = dur[i]
    
    # Build formula string with voice name
    voiceName$ = "voice_" + string$(i)
    Formula (part): d, d + voiceDur, 1, 1, "Sound_'voiceName$'(x - 'd')"
endfor

# === Combine all 8 channels ===
selectObject: ch[1], ch[2]
Combine to stereo
pair12 = selected("Sound")

selectObject: ch[3], ch[4]
Combine to stereo
pair34 = selected("Sound")

selectObject: ch[5], ch[6]
Combine to stereo
pair56 = selected("Sound")

selectObject: ch[7], ch[8]
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
Scale peak: 0.95
Rename: originalName$ + "_canon8ch_" + presetName$

# === Info ===
writeInfoLine: "=== 8-Channel Canon ==="
appendInfoLine: "Source: ", originalName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
for i from 1 to 8
    if semi[i] >= 0
        appendInfoLine: "Ch", i, ": +", fixed$(semi[i], 1), " st, delay ", fixed$(delay[i], 2), "s"
    else
        appendInfoLine: "Ch", i, ": ", fixed$(semi[i], 1), " st, delay ", fixed$(delay[i], 2), "s"
    endif
endfor

# === Cleanup ===
select Sound base_resampled
Remove

for i from 1 to 8
    removeObject: voice[i], ch[i]
endfor

removeObject: pair12, pair34, pair56, pair78, quad1234, quad5678

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    Select outer viewport: 0, 8, 0, 8

    # ----------------------------------------------------------
    # Title
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.45
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.95, "half", "##8-Channel Canon##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.25, "half",
        ... originalName$ + "  |  " + presetName$
        ... + "  |  " + fixed$(outputDur, 2) + " s"

    # ----------------------------------------------------------
    # Canon timeline diagram
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.50, 3.50
    Select inner viewport: 0.55, 7.65, 0.60, 3.40

    Axes: -outputDur * 0.02, outputDur * 1.05, 0, 9
    Paint rectangle: "{0.96, 0.96, 0.96}",
        ... -outputDur * 0.02, outputDur * 1.05, 0, 9

    # Vertical time grid
    Colour: "{0.88, 0.88, 0.88}"
    timeStep = 0.5
    if outputDur > 5
        timeStep = 1.0
    endif
    gridT = timeStep
    while gridT < outputDur
        Draw line: gridT, 0, gridT, 9
        gridT = gridT + timeStep
    endwhile

    # Draw each channel bar
    for i from 1 to 8
        yPos = 9 - i

        # Colour: warm (positive semitones) / cool (negative)
        if semi[i] >= 0
            cFrac = min(semi[i] / 24, 1)
            cR = 0.40 + cFrac * 0.45
            cG = 0.48 - cFrac * 0.18
            cB = 0.72 - cFrac * 0.45
        else
            cFrac = min(-semi[i] / 24, 1)
            cR = 0.35 - cFrac * 0.10
            cG = 0.48 + cFrac * 0.18
            cB = 0.72 + cFrac * 0.18
        endif
        barCol$ = "{" + fixed$(cR, 2) + "," + fixed$(cG, 2) + "," + fixed$(cB, 2) + "}"

        Paint rectangle: barCol$, delay[i], delay[i] + dur[i],
            ... yPos + 0.10, yPos + 0.82

        # Bar outline
        Colour: "{0.40, 0.40, 0.40}"
        Line width: 1
        Draw rectangle: delay[i], delay[i] + dur[i],
            ... yPos + 0.10, yPos + 0.82

        # Label inside bar: channel + semitones + delay
        Font size: 6
        Colour: "White"
        if semi[i] >= 0
            semiLbl$ = "+" + fixed$(semi[i], 1)
        else
            semiLbl$ = fixed$(semi[i], 1)
        endif
        barMidX = delay[i] + dur[i] * 0.5
        barMidY = yPos + 0.46
        # Only draw label if bar is wide enough
        if dur[i] > outputDur * 0.08
            Text: barMidX, "centre", barMidY, "half",
                ... "Ch" + string$(i) + "  " + semiLbl$ + " st"
        endif

        # Delay label at left edge (outside bar if needed)
        Font size: 5
        Colour: "{0.40, 0.40, 0.40}"
        if delay[i] > outputDur * 0.04
            Text: delay[i] - outputDur * 0.01, "right", barMidY, "half",
                ... fixed$(delay[i], 2) + "s"
        endif
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Marks bottom every: 1, timeStep, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Canon timeline  (colour = pitch direction,  warm = up,  cool = down)"

    # Channel labels on left
    for i from 1 to 8
        yPos = 9 - i
        Font size: 6
        Colour: "{0.35, 0.35, 0.35}"
        Text: -outputDur * 0.015, "right", yPos + 0.46, "half", string$(i)
    endfor

    # ----------------------------------------------------------
    # Spectrogram of stereo downmix (shows pitch canon structure)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 3.58, 4.88
    Select inner viewport: 0.55, 7.65, 3.65, 4.80

    # Create mono downmix of the 8-channel result
    selectObject: result
    vizMix = Convert to mono
    To Spectrogram: 0.02, 5000, 0.005, 20, "Gaussian"
    specMix = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    removeObject: specMix, vizMix

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Canon spectrogram  (mono downmix — stacked pitch entries)"

    # ----------------------------------------------------------
    # Summary panel
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.98, 6.08
    Select inner viewport: 0.55, 7.65, 5.04, 6.02
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.88, "half", "##Summary##"

    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"

    # Build compact interval list
    intList$ = ""
    for i from 1 to 8
        if i > 1
            intList$ = intList$ + "  "
        endif
        if semi[i] >= 0
            intList$ = intList$ + "+" + fixed$(semi[i], 1)
        else
            intList$ = intList$ + fixed$(semi[i], 1)
        endif
    endfor

    # Build compact delay list
    delList$ = ""
    for i from 1 to 8
        if i > 1
            delList$ = delList$ + "  "
        endif
        delList$ = delList$ + fixed$(delay[i], 2)
    endfor

    Text: 0.02, "left", 0.68, "half",
        ... "Preset: " + presetName$
        ... + "  |  Source: " + originalName$
        ... + "  |  Duration: " + fixed$(outputDur, 2) + " s"
    Text: 0.02, "left", 0.44, "half",
        ... "Semitones:  " + intList$
    Text: 0.02, "left", 0.20, "half",
        ... "Delays (s): " + delList$

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# === Done ===
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Output: 8-channel, ", fixed$(outputDur, 2), "s"

if play_result
    selectObject: result
    Play
endif

selectObject: result