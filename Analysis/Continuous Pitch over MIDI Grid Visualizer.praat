# ========================================================================================
# Praat AudioTools - Continuous_Pitch_over_MIDI_Grid_Visualizer.praat
# Author: Shai Cohen
# Version: 2.2 (2026)
# License: MIT License
#
# Description:
#   Visualizes measured continuous F0 on a 12-TET MIDI reference grid.
#   The pitch curve is NOT quantized: m = 69 + 12*log2(f/440).
#   Unvoiced frames remain gaps. Loudness may control colour, width,
#   or dot size. Diagnostic panels show cents deviation from the nearest
#   equal-tempered note and the measured intensity/voicing context.
#
# Changelog v2.2:
#   - Analysis is performed on the strongest-RMS channel for multichannel input,
#     avoiding phase-cancelling fold-downs while preserving the original Sound.
#   - Smoothing is now voiced-segment aware: it never borrows values across an
#     unvoiced gap.
#   - Rebuilt visualization in the AudioTools 8-unit house width with explicit
#     title strips and separate data viewports.
#   - Added measured cents-deviation and intensity/voicing diagnostic panels.
#   - Fixed Grayscale Loudness so louder frames are darker/more visible.
#   - Renamed misleading "Octave Spiral" colour mode to
#     "PitchClass + Octave Brightness" (it is a colour mapping, not a spiral).
#   - Adaptive time-grid spacing prevents dense vertical clutter on long sounds.
#   - Added Play_sound option; playback is no longer unconditional.
#   - Added validation for manual MIDI and intensity mapping ranges.
# ========================================================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

soundID = selected("Sound")
sound$ = selected$("Sound")

form Continuous Pitch MIDI Grid Visualizer v2.2
    comment === Analysis ===
    positive Pitch_floor_Hz 75
    positive Pitch_ceiling_Hz 600
    positive Time_step_s 0.01
    comment (multichannel: strongest-RMS channel is analyzed)
    comment === MIDI Reference Range ===
    boolean Auto_midi_range 1
    integer Manual_midi_min 48
    integer Manual_midi_max 84
    positive Midi_padding 3
    comment === Smoothing (continuous MIDI pitch) ===
    optionmenu Smoothing: 1
        option No smoothing
        option Median 3-frame
        option Median 5-frame
        option Moving average 3-frame
    comment === Colour Encoding ===
    optionmenu Color_scheme: 1
        option Pitch+Loudness Rainbow
        option PitchClass+Loudness Wheel
        option Grayscale Loudness
        option Intensity Heatmap
        option PitchClass + Octave Brightness
    comment === Mark Style ===
    optionmenu Line_style: 1
        option Thin continuous line
        option Thickness varies with loudness
        option Dots with size varies with loudness
    positive Min_dot_size_mm 0.8
    positive Max_dot_size_mm 3.5
    comment === Display ===
    boolean Show_all_semitones 1
    boolean Show_note_labels 1
    boolean Show_time_grid 0
    comment === Loudness Mapping ===
    positive Intensity_min_dB 40
    positive Intensity_max_dB 80
    boolean Use_log_loudness 1
    comment === Output ===
    boolean Play_sound 0
endform

# --- Validation ---
if pitch_ceiling_Hz <= pitch_floor_Hz
    pitch_ceiling_Hz = pitch_floor_Hz * 2
endif
if time_step_s <= 0
    time_step_s = 0.01
endif
if manual_midi_max <= manual_midi_min
    manual_midi_max = manual_midi_min + 12
endif
if intensity_max_dB <= intensity_min_dB
    intensity_max_dB = intensity_min_dB + 20
endif
if max_dot_size_mm < min_dot_size_mm
    tempDot = max_dot_size_mm
    max_dot_size_mm = min_dot_size_mm
    min_dot_size_mm = tempDot
endif

# ========================================================================================
# HELPER PROCEDURES
# ========================================================================================

procedure hzToMidi: .hz
    if .hz > 0
        .midi = 69 + 12 * log2(.hz / 440)
    else
        .midi = undefined
    endif
endproc

procedure mapToRange: .value, .fromMin, .fromMax, .toMin, .toMax
    if .fromMax <= .fromMin
        .result = (.toMin + .toMax) / 2
    else
        .value2 = max(.fromMin, min(.fromMax, .value))
        .result = .toMin + (.value2 - .fromMin) / (.fromMax - .fromMin) * (.toMax - .toMin)
    endif
endproc

procedure loudnessNorm: .db
    .norm = (.db - intensity_min_dB) / (intensity_max_dB - intensity_min_dB)
    .norm = max(0, min(1, .norm))
    if use_log_loudness
        .norm = log10(.norm * 9 + 1)
    endif
    .result = .norm
endproc

procedure getMidiNoteName: .midi
    .noteClass = .midi - 12 * floor(.midi / 12)
    .octave = floor(.midi / 12) - 1
    if .noteClass = 0
        .noteName$ = "C"
    elsif .noteClass = 1
        .noteName$ = "C#"
    elsif .noteClass = 2
        .noteName$ = "D"
    elsif .noteClass = 3
        .noteName$ = "D#"
    elsif .noteClass = 4
        .noteName$ = "E"
    elsif .noteClass = 5
        .noteName$ = "F"
    elsif .noteClass = 6
        .noteName$ = "F#"
    elsif .noteClass = 7
        .noteName$ = "G"
    elsif .noteClass = 8
        .noteName$ = "G#"
    elsif .noteClass = 9
        .noteName$ = "A"
    elsif .noteClass = 10
        .noteName$ = "A#"
    else
        .noteName$ = "B"
    endif
    .fullName$ = .noteName$ + string$(.octave)
endproc

procedure pitchClassToRGB: .midi, .brightness
    .noteClass = .midi - 12 * floor(.midi / 12)
    .h = (.noteClass / 12.0) * 360
    .s = 0.80
    .v = .brightness
    .c = .v * .s
    .x = .c * (1 - abs(((.h / 60) mod 2) - 1))
    .m = .v - .c
    if .h < 60
        .r = .c
        .g = .x
        .b = 0
    elsif .h < 120
        .r = .x
        .g = .c
        .b = 0
    elsif .h < 180
        .r = 0
        .g = .c
        .b = .x
    elsif .h < 240
        .r = 0
        .g = .x
        .b = .c
    elsif .h < 300
        .r = .x
        .g = 0
        .b = .c
    else
        .r = .c
        .g = 0
        .b = .x
    endif
    .red = .r + .m
    .green = .g + .m
    .blue = .b + .m
endproc

procedure pitchHeightToRGB: .midi, .brightness
    @mapToRange: .midi, currentMidiMin, currentMidiMax, 0, 1
    .h = (1 - mapToRange.result) * 240
    .s = 0.90
    .v = .brightness
    .c = .v * .s
    .x = .c * (1 - abs(((.h / 60) mod 2) - 1))
    .m = .v - .c
    if .h < 60
        .r = .c
        .g = .x
        .b = 0
    elsif .h < 120
        .r = .x
        .g = .c
        .b = 0
    elsif .h < 180
        .r = 0
        .g = .c
        .b = .x
    elsif .h < 240
        .r = 0
        .g = .x
        .b = .c
    elsif .h < 300
        .r = .x
        .g = 0
        .b = .c
    else
        .r = .c
        .g = 0
        .b = .x
    endif
    .red = .r + .m
    .green = .g + .m
    .blue = .b + .m
endproc

procedure octaveBrightnessRGB: .midi, .brightness
    .noteClass = .midi - 12 * floor(.midi / 12)
    .octave = floor(.midi / 12) - 1
    .h = (.noteClass / 12.0) * 360
    @mapToRange: .midi, currentMidiMin, currentMidiMax, 0, 1
    .heightNorm = mapToRange.result
    .v = .brightness * (0.45 + 0.55 * .heightNorm)
    .s = 0.85
    .c = .v * .s
    .x = .c * (1 - abs(((.h / 60) mod 2) - 1))
    .m = .v - .c
    if .h < 60
        .r = .c
        .g = .x
        .b = 0
    elsif .h < 120
        .r = .x
        .g = .c
        .b = 0
    elsif .h < 180
        .r = 0
        .g = .c
        .b = .x
    elsif .h < 240
        .r = 0
        .g = .x
        .b = .c
    elsif .h < 300
        .r = .x
        .g = 0
        .b = .c
    else
        .r = .c
        .g = 0
        .b = .x
    endif
    .red = .r + .m
    .green = .g + .m
    .blue = .b + .m
endproc

procedure chooseColour: .midi, .db
    @loudnessNorm: .db
    .loud = loudnessNorm.result
    .brightness = 0.30 + 0.70 * .loud
    if color_scheme = 1
        @pitchHeightToRGB: .midi, .brightness
        .r = pitchHeightToRGB.red
        .g = pitchHeightToRGB.green
        .b = pitchHeightToRGB.blue
    elsif color_scheme = 2
        @pitchClassToRGB: .midi, .brightness
        .r = pitchClassToRGB.red
        .g = pitchClassToRGB.green
        .b = pitchClassToRGB.blue
    elsif color_scheme = 3
        # Louder = darker, so high loudness remains visible on white.
        .shade = 0.82 - 0.72 * .loud
        .r = .shade
        .g = .shade
        .b = .shade
    elsif color_scheme = 4
        .heat = .loud
        if .heat < 0.33
            .r = 0
            .g = .heat * 3
            .b = 1 - .heat * 3
        elsif .heat < 0.66
            .local = (.heat - 0.33) * 3
            .r = .local
            .g = 1
            .b = 0
        else
            .local = (.heat - 0.66) * 3
            .r = 1
            .g = 1 - .local
            .b = 0
        endif
    else
        @octaveBrightnessRGB: .midi, .brightness
        .r = octaveBrightnessRGB.red
        .g = octaveBrightnessRGB.green
        .b = octaveBrightnessRGB.blue
    endif
    .colour$ = "{" + fixed$(.r, 5) + ", " + fixed$(.g, 5) + ", " + fixed$(.b, 5) + "}"
    .loudNorm = .loud
endproc

# ========================================================================================
# MAIN ANALYSIS
# ========================================================================================

selectObject: soundID
duration = Get total duration
startTime = Get start time
endTime = Get end time
nChannels = Get number of channels

clearinfo
writeInfoLine: "=== Continuous Pitch MIDI Grid Visualizer v2.2 ==="
appendInfoLine: "Sound: ", sound$
appendInfoLine: "Duration: ", fixed$(duration, 3), " s | Channels: ", nChannels

# --- Strongest-RMS analysis channel ---
analysisChannel = 1
strongestRMS = -1
if nChannels > 1
    for ch from 1 to nChannels
        selectObject: soundID
        Extract one channel: ch
        tmpCh = selected("Sound")
        rmsCh = Get root-mean-square: 0, 0
        if rmsCh > strongestRMS
            strongestRMS = rmsCh
            analysisChannel = ch
        endif
        removeObject: tmpCh
    endfor
    selectObject: soundID
    Extract one channel: analysisChannel
    analysisSound = selected("Sound")
    appendInfoLine: "Analysis channel: ", analysisChannel, " (strongest RMS)"
else
    analysisSound = soundID
    strongestRMS = Get root-mean-square: 0, 0
    appendInfoLine: "Analysis channel: mono"
endif

appendInfoLine: "Extracting pitch and intensity..."
selectObject: analysisSound
pitchID = To Pitch: time_step_s, pitch_floor_Hz, pitch_ceiling_Hz
selectObject: analysisSound
intensityID = To Intensity: pitch_floor_Hz, time_step_s, "yes"

selectObject: pitchID
numFrames = Get number of frames
if numFrames < 2
    exitScript: "Pitch analysis produced too few frames. Increase duration or reduce Time step."
endif

voicedCount = 0
intFoundMin = 1e9
intFoundMax = -1e9

for i from 1 to numFrames
    selectObject: pitchID
    t_'i' = Get time from frame number: i
    f0_'i' = Get value in frame: i, "Hertz"
    if f0_'i' <> undefined and f0_'i' > 0
        @hzToMidi: f0_'i'
        midiRaw_'i' = hzToMidi.midi
        midiNote_'i' = hzToMidi.midi
        voiced_'i' = 1
        voicedCount += 1
    else
        midiRaw_'i' = undefined
        midiNote_'i' = undefined
        voiced_'i' = 0
    endif

    selectObject: intensityID
    intensity_'i' = Get value at time: t_'i', "Cubic"
    if intensity_'i' = undefined
        intensity_'i' = intensity_min_dB
    endif
    if intensity_'i' < intFoundMin
        intFoundMin = intensity_'i'
    endif
    if intensity_'i' > intFoundMax
        intFoundMax = intensity_'i'
    endif
endfor

# --- Voiced-segment-aware smoothing ---
if smoothing > 1
    appendInfoLine: "Smoothing: ", smoothing$
    for i from 1 to numFrames
        smoothedMidi_'i' = midiNote_'i'
    endfor

    for i from 1 to numFrames
        if voiced_'i' = 1
            if smoothing = 2
                if i > 1 and i < numFrames
                    im1 = i - 1
                    ip1 = i + 1
                    if voiced_'im1' = 1 and voiced_'ip1' = 1
                        a = midiNote_'im1'
                        b = midiNote_'i'
                        c = midiNote_'ip1'
                        if a > b
                            temp = a
                            a = b
                            b = temp
                        endif
                        if b > c
                            temp = b
                            b = c
                            c = temp
                        endif
                        if a > b
                            temp = a
                            a = b
                            b = temp
                        endif
                        smoothedMidi_'i' = b
                    endif
                endif
            elsif smoothing = 3
                if i > 2 and i < numFrames - 1
                    im2 = i - 2
                    im1 = i - 1
                    ip1 = i + 1
                    ip2 = i + 2
                    if voiced_'im2' = 1 and voiced_'im1' = 1 and voiced_'ip1' = 1 and voiced_'ip2' = 1
                        sort_1 = midiNote_'im2'
                        sort_2 = midiNote_'im1'
                        sort_3 = midiNote_'i'
                        sort_4 = midiNote_'ip1'
                        sort_5 = midiNote_'ip2'
                        for pass from 1 to 4
                            for k from 1 to 5 - pass
                                k1 = k + 1
                                if sort_'k' > sort_'k1'
                                    temp = sort_'k'
                                    sort_'k' = sort_'k1'
                                    sort_'k1' = temp
                                endif
                            endfor
                        endfor
                        smoothedMidi_'i' = sort_3
                    endif
                endif
            else
                if i > 1 and i < numFrames
                    im1 = i - 1
                    ip1 = i + 1
                    if voiced_'im1' = 1 and voiced_'ip1' = 1
                        smoothedMidi_'i' = (midiNote_'im1' + midiNote_'i' + midiNote_'ip1') / 3
                    endif
                endif
            endif
        endif
    endfor

    for i from 1 to numFrames
        if voiced_'i' = 1
            midiNote_'i' = smoothedMidi_'i'
        endif
    endfor
else
    appendInfoLine: "Smoothing: none"
endif

# --- Measured MIDI range and deviation statistics after smoothing ---
midiMinFound = 1000
midiMaxFound = -1000
sumAbsCents = 0
maxAbsCents = 0
if voicedCount > 0
    for i from 1 to numFrames
        if voiced_'i' = 1
            m = midiNote_'i'
            if m < midiMinFound
                midiMinFound = m
            endif
            if m > midiMaxFound
                midiMaxFound = m
            endif
            cents_'i' = 100 * (m - round(m))
            absC = abs(cents_'i')
            sumAbsCents += absC
            if absC > maxAbsCents
                maxAbsCents = absC
            endif
        else
            cents_'i' = undefined
        endif
    endfor
    meanAbsCents = sumAbsCents / voicedCount
else
    meanAbsCents = 0
endif

if auto_midi_range and voicedCount > 0
    currentMidiMin = floor(midiMinFound) - midi_padding
    currentMidiMax = ceiling(midiMaxFound) + midi_padding
    if currentMidiMax <= currentMidiMin
        currentMidiMax = currentMidiMin + 12
    endif
    appendInfoLine: "Auto MIDI range: ", currentMidiMin, " - ", currentMidiMax
else
    currentMidiMin = manual_midi_min
    currentMidiMax = manual_midi_max
    appendInfoLine: "Manual MIDI range: ", currentMidiMin, " - ", currentMidiMax
endif

voicedPercent = 100 * voicedCount / numFrames
appendInfoLine: "Voiced frames: ", voicedCount, "/", numFrames, " (", fixed$(voicedPercent, 1), "%)"
if voicedCount > 0
    appendInfoLine: "Measured continuous MIDI span: ", fixed$(midiMinFound, 2), " - ", fixed$(midiMaxFound, 2)
    appendInfoLine: "Mean |deviation from nearest 12-TET note|: ", fixed$(meanAbsCents, 1), " cents"
endif

# Adaptive time-grid step
if duration <= 1
    timeGridStep = 0.1
elsif duration <= 2.5
    timeGridStep = 0.25
elsif duration <= 5
    timeGridStep = 0.5
elsif duration <= 10
    timeGridStep = 1
elsif duration <= 20
    timeGridStep = 2
elsif duration <= 50
    timeGridStep = 5
else
    timeGridStep = 10
endif

# ========================================================================================
# VISUALIZATION
# ========================================================================================

Erase all

# --- Title strip ---
Select outer viewport: 0, 8, 0.0, 0.50
Select inner viewport: 0, 8, 0.0, 0.50
Axes: 0, 1, 0, 1
Colour: "Black"
Font size: 13
Text: 0.5, "centre", 0.68, "half", "Continuous Pitch over MIDI Grid"
Font size: 7
Colour: "{0.35, 0.35, 0.40}"
subtitle$ = sound$ + " | ch " + string$(analysisChannel) + " | m = 69 + 12 log2(f/440) | 12-TET grid is a reference, not quantization"
Text: 0.5, "centre", 0.20, "half", subtitle$

# --- Main panel title ---
Select outer viewport: 0, 8, 0.55, 0.82
Select inner viewport: 0, 8, 0.55, 0.82
Axes: 0, 1, 0, 1
Font size: 8
Colour: "Black"
Text: 0.01, "left", 0.5, "half", "A  MEASURED CONTINUOUS F0 ON MIDI REFERENCE GRID"

# --- Main panel data ---
Select inner viewport: 0.78, 7.72, 0.88, 3.25
Axes: startTime, endTime, currentMidiMin - 0.5, currentMidiMax + 0.5
Colour: "{0.985, 0.985, 0.985}"
Paint rectangle: "{0.985, 0.985, 0.985}", startTime, endTime, currentMidiMin - 0.5, currentMidiMax + 0.5

# Horizontal 12-TET reference lines
for midiLine from currentMidiMin to currentMidiMax
    noteClass = midiLine - 12 * floor(midiLine / 12)
    if noteClass = 0
        Colour: "{0.65, 0.65, 0.65}"
        Line width: 1.5
        Draw line: startTime, midiLine, endTime, midiLine
    elsif show_all_semitones
        Colour: "{0.90, 0.90, 0.90}"
        Line width: 0.5
        Draw line: startTime, midiLine, endTime, midiLine
    endif
endfor

# Adaptive vertical time grid
if show_time_grid
    firstGrid = ceiling(startTime / timeGridStep) * timeGridStep
    gridT = firstGrid
    Colour: "{0.91, 0.91, 0.91}"
    Line width: 0.5
    while gridT <= endTime
        Draw line: gridT, currentMidiMin - 0.5, gridT, currentMidiMax + 0.5
        gridT += timeGridStep
    endwhile
endif

# Pitch rendering: lines or dots, never across unvoiced gaps
if line_style = 3
    for i from 1 to numFrames
        if voiced_'i' = 1
            @chooseColour: midiNote_'i', intensity_'i'
            col$ = chooseColour.colour$
            @mapToRange: intensity_'i', intensity_min_dB, intensity_max_dB, min_dot_size_mm, max_dot_size_mm
            dotSize = mapToRange.result
            Paint circle: col$, t_'i', midiNote_'i', dotSize
        endif
    endfor
else
    for i from 1 to numFrames - 1
        i1 = i + 1
        if voiced_'i' = 1 and voiced_'i1' = 1
            mCurr = midiNote_'i'
            mNext = midiNote_'i1'
            intMean = (intensity_'i' + intensity_'i1') / 2
            mMean = (mCurr + mNext) / 2
            @chooseColour: mMean, intMean
            Colour: chooseColour.colour$
            if line_style = 1
                Line width: 1.4
            else
                @mapToRange: intMean, intensity_min_dB, intensity_max_dB, 0.6, 4.2
                Line width: mapToRange.result
            endif
            Draw line: t_'i', mCurr, t_'i1', mNext
        endif
    endfor
endif

# Frame and time axis
Select inner viewport: 0.78, 7.72, 0.88, 3.25
Axes: startTime, endTime, currentMidiMin - 0.5, currentMidiMax + 0.5
Colour: "Black"
Line width: 1
Draw inner box
Font size: 7
Marks bottom: 5, "yes", "yes", "no"
Text bottom: "yes", "Time (s)"

# Dedicated note-label strip (prevents labels colliding with data)
if show_note_labels
    Select inner viewport: 0.05, 0.72, 0.88, 3.25
    Axes: 0, 1, currentMidiMin - 0.5, currentMidiMax + 0.5
    Font size: 6
    Colour: "{0.35, 0.35, 0.35}"
    labelEverySemitone = 0
    if currentMidiMax - currentMidiMin <= 18 and show_all_semitones
        labelEverySemitone = 1
    endif
    for midiLine from currentMidiMin to currentMidiMax
        noteClass = midiLine - 12 * floor(midiLine / 12)
        if labelEverySemitone or noteClass = 0
            @getMidiNoteName: midiLine
            Text: 0.96, "right", midiLine, "half", getMidiNoteName.fullName$
        endif
    endfor
endif

# --- Panel B title ---
Select outer viewport: 0, 4, 3.42, 3.68
Select inner viewport: 0, 4, 3.42, 3.68
Axes: 0, 1, 0, 1
Font size: 8
Colour: "Black"
Text: 0.02, "left", 0.5, "half", "B  DEVIATION FROM NEAREST 12-TET NOTE"

# --- Panel B data: cents ---
Select inner viewport: 0.60, 3.80, 3.74, 4.64
Axes: startTime, endTime, -50, 50
Colour: "{0.985, 0.985, 0.985}"
Paint rectangle: "{0.985, 0.985, 0.985}", startTime, endTime, -50, 50
Colour: "{0.72, 0.72, 0.72}"
Draw line: startTime, 0, endTime, 0
Dotted line
Draw line: startTime, 25, endTime, 25
Draw line: startTime, -25, endTime, -25
Solid line
Colour: "{0.25, 0.45, 0.72}"
Line width: 1.2
for i from 1 to numFrames - 1
    i1 = i + 1
    if voiced_'i' = 1 and voiced_'i1' = 1
        Draw line: t_'i', cents_'i', t_'i1', cents_'i1'
    endif
endfor
Colour: "Black"
Line width: 1
Draw inner box
Font size: 6
Marks left: 3, "yes", "yes", "no"
Marks bottom: 4, "yes", "yes", "no"
Text left: "yes", "cents"
Text bottom: "yes", "Time (s)"

# --- Panel C title ---
Select outer viewport: 4, 8, 3.42, 3.68
Select inner viewport: 4, 8, 3.42, 3.68
Axes: 0, 1, 0, 1
Font size: 8
Colour: "Black"
Text: 0.02, "left", 0.5, "half", "C  INTENSITY + VOICING CONTEXT"

# --- Panel C data ---
intYMin = min(intensity_min_dB, intFoundMin) - 2
intYMax = max(intensity_max_dB, intFoundMax) + 2
if intYMax <= intYMin
    intYMax = intYMin + 20
endif
Select inner viewport: 4.62, 7.80, 3.74, 4.64
Axes: startTime, endTime, intYMin, intYMax
Colour: "{0.985, 0.985, 0.985}"
Paint rectangle: "{0.985, 0.985, 0.985}", startTime, endTime, intYMin, intYMax

# Shade unvoiced runs
inGap = 0
gapStart = startTime
for i from 1 to numFrames
    if voiced_'i' = 0 and inGap = 0
        gapStart = t_'i' - time_step_s / 2
        gapStart = max(startTime, gapStart)
        inGap = 1
    elsif voiced_'i' = 1 and inGap = 1
        gapEnd = t_'i' - time_step_s / 2
        Paint rectangle: "{0.92, 0.92, 0.92}", gapStart, gapEnd, intYMin, intYMax
        inGap = 0
    endif
endfor
if inGap = 1
    Paint rectangle: "{0.92, 0.92, 0.92}", gapStart, endTime, intYMin, intYMax
endif

# Configured loudness-mapping bounds
Colour: "{0.65, 0.65, 0.65}"
Dotted line
Draw line: startTime, intensity_min_dB, endTime, intensity_min_dB
Draw line: startTime, intensity_max_dB, endTime, intensity_max_dB
Solid line

# Intensity curve
Colour: "{0.78, 0.38, 0.20}"
Line width: 1.2
for i from 1 to numFrames - 1
    i1 = i + 1
    Draw line: t_'i', intensity_'i', t_'i1', intensity_'i1'
endfor
Colour: "Black"
Line width: 1
Draw inner box
Font size: 6
Marks left: 3, "yes", "yes", "no"
Marks bottom: 4, "yes", "yes", "no"
Text left: "yes", "dB"
Text bottom: "yes", "Time (s)"

# --- Footer summary ---
Select outer viewport: 0, 8, 4.86, 5.28
Select inner viewport: 0, 8, 4.86, 5.28
Axes: 0, 1, 0, 1
Font size: 7
Colour: "{0.30, 0.30, 0.34}"
if color_scheme = 1
    colorName$ = "pitch-height hue + loudness"
elsif color_scheme = 2
    colorName$ = "pitch-class hue + loudness"
elsif color_scheme = 3
    colorName$ = "grayscale loudness"
elsif color_scheme = 4
    colorName$ = "intensity heatmap"
else
    colorName$ = "pitch-class hue + octave brightness"
endif
if line_style = 1
    styleName$ = "line"
elsif line_style = 2
    styleName$ = "loudness width"
else
    styleName$ = "loudness dots"
endif
summary$ = "voiced " + fixed$(voicedPercent, 1) + "% | mean |cents| " + fixed$(meanAbsCents, 1) + " | smoothing: " + smoothing$ + " | " + styleName$ + " | " + colorName$
Text: 0.5, "centre", 0.58, "half", summary$
Font size: 6
Colour: "{0.45, 0.45, 0.48}"
Text: 0.5, "centre", 0.18, "half", "Grey in panel C = unvoiced; pitch lines are never connected across unvoiced gaps."

# Reset picture state
Font size: 10
Colour: "Black"
Line width: 1

# ========================================================================================
# CLEANUP / OPTIONAL PLAYBACK
# ========================================================================================

removeObject: pitchID, intensityID
if nChannels > 1
    removeObject: analysisSound
endif
selectObject: soundID

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Frames: ", numFrames
appendInfoLine: "MIDI display range: ", currentMidiMin, " - ", currentMidiMax

if play_sound
    Play
endif
