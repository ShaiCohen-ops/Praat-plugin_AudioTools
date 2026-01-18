# ========================================================================================
# Praat AudioTools - Continuous_Pitch_over_MIDI_Grid_Visualizer.praat
# Author: Shai Cohen
# Version: 2.1 (2025) - Fixed array syntax
# ========================================================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

soundID = selected("Sound")
sound$ = selected$("Sound")

form Continuous Pitch MIDI Grid Visualizer v2.1
    comment === Analysis ===
    positive Pitch_floor 75
    positive Pitch_ceiling 600
    positive Time_step 0.01
    comment === MIDI Range ===
    boolean Auto_midi_range 1
    integer Manual_midi_min 48
    integer Manual_midi_max 84
    positive Midi_padding 3
    comment === Smoothing ===
    optionmenu Smoothing: 1
        option No smoothing
        option Median 3-frame
        option Median 5-frame
        option Moving average
    comment === Color Scheme ===
    optionmenu Color_scheme: 1
        option Pitch+Loudness Rainbow
        option PitchClass+Loudness Wheel
        option Grayscale Loudness
        option Intensity Heatmap
        option Octave Spiral
    comment === Line Style ===
    optionmenu Line_style: 1
        option Thin continuous line
        option Thickness varies with loudness
        option Dots with size varies with loudness
    positive Min_dot_size 0.8
    positive Max_dot_size 3.5
    comment === Display ===
    boolean Show_all_semitones 1
    boolean Show_note_labels 1
    boolean Show_time_grid 0
    comment === Intensity ===
    positive Intensity_min_db 40
    positive Intensity_max_db 80
    boolean Use_log_loudness 1
endform

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
    .value = max(.fromMin, min(.fromMax, .value))
    .result = .toMin + (.value - .fromMin) / (.fromMax - .fromMin) * (.toMax - .toMin)
endproc

procedure logCompress: .db, .minDb, .maxDb
    .normalized = (.db - .minDb) / (.maxDb - .minDb)
    .normalized = max(0, min(1, .normalized))
    if .normalized > 0
        .result = (log10(.normalized * 9 + 1)) / log10(10)
    else
        .result = 0
    endif
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
    elsif .noteClass = 11
        .noteName$ = "B"
    endif
    
    .fullName$ = .noteName$ + string$(.octave)
endproc

procedure medianFilter3: .i
    if .i = 1 or .i = numFrames
        .result = midiNote_'.i'
    else
        .iPrev = .i - 1
        .iNext = .i + 1
        .valPrev = midiNote_'.iPrev'
        .valCurr = midiNote_'.i'
        .valNext = midiNote_'.iNext'
        
        if .valPrev <> undefined and .valCurr <> undefined and .valNext <> undefined
            .a = .valPrev
            .b = .valCurr
            .c = .valNext
            
            if .a <= .b and .b <= .c
                .result = .b
            elsif .a <= .c and .c <= .b
                .result = .c
            elsif .b <= .a and .a <= .c
                .result = .a
            elsif .b <= .c and .c <= .a
                .result = .c
            elsif .c <= .a and .a <= .b
                .result = .a
            else
                .result = .b
            endif
        else
            .result = midiNote_'.i'
        endif
    endif
endproc

procedure medianFilter5: .i
    if .i <= 2 or .i >= numFrames - 1
        .result = midiNote_'.i'
    else
        # Collect up to 5 values
        .count = 0
        for .offset from -2 to 2
            .idx = .i + .offset
            .val = midiNote_'.idx'
            if .val <> undefined
                .count = .count + 1
                .sortVal_'.count' = .val
            endif
        endfor
        
        if .count >= 3
            # Bubble sort
            for .pass from 1 to .count - 1
                for .k from 1 to .count - .pass
                    .k1 = .k + 1
                    .v1 = .sortVal_'.k'
                    .v2 = .sortVal_'.k1'
                    if .v1 > .v2
                        .sortVal_'.k' = .v2
                        .sortVal_'.k1' = .v1
                    endif
                endfor
            endfor
            .medianIdx = floor(.count / 2) + 1
            .result = .sortVal_'.medianIdx'
        else
            .result = midiNote_'.i'
        endif
    endif
endproc

procedure movingAverage: .i
    if .i = 1 or .i = numFrames
        .result = midiNote_'.i'
    else
        .count = 0
        .sum = 0
        for .offset from -1 to 1
            .idx = .i + .offset
            .val = midiNote_'.idx'
            if .val <> undefined
                .sum = .sum + .val
                .count = .count + 1
            endif
        endfor
        if .count > 0
            .result = .sum / .count
        else
            .result = midiNote_'.i'
        endif
    endif
endproc

procedure pitchClassToRGB: .midi, .brightness
    .noteClass = .midi - 12 * floor(.midi / 12)
    .hue = .noteClass / 12.0
    
    .h = .hue * 360
    .s = 0.8
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
    .hue = mapToRange.result
    
    .h = (1 - .hue) * 240
    .s = 0.9
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

procedure octaveSpiralRGB: .midi, .brightness
    .noteClass = .midi - 12 * floor(.midi / 12)
    .octave = floor(.midi / 12) - 1
    
    .hue = (.noteClass / 12.0) * 360
    
    .octaveFactor = (.octave - 2) / 6.0
    .octaveFactor = max(0, min(1, .octaveFactor))
    
    .finalBrightness = .brightness * (0.4 + 0.6 * .octaveFactor)
    
    .s = 0.85
    .v = .finalBrightness
    
    .c = .v * .s
    .x = .c * (1 - abs(((.hue / 60) mod 2) - 1))
    .m = .v - .c
    
    if .hue < 60
        .r = .c
        .g = .x
        .b = 0
    elsif .hue < 120
        .r = .x
        .g = .c
        .b = 0
    elsif .hue < 180
        .r = 0
        .g = .c
        .b = .x
    elsif .hue < 240
        .r = 0
        .g = .x
        .b = .c
    elsif .hue < 300
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

# ========================================================================================
# MAIN SCRIPT
# ========================================================================================

selectObject: soundID
duration = Get total duration
startTime = Get start time
endTime = Get end time

clearinfo
writeInfoLine: "=== Continuous Pitch MIDI Grid Visualizer v2.1 ==="
appendInfoLine: "Sound: ", sound$
appendInfoLine: "Duration: ", fixed$(duration, 3), " s"
appendInfoLine: ""

# ========================================================================================
# STEP 1: Extract Pitch and Intensity
# ========================================================================================

appendInfoLine: "Extracting pitch..."
selectObject: soundID
pitchID = To Pitch: time_step, pitch_floor, pitch_ceiling

appendInfoLine: "Extracting intensity..."
selectObject: soundID
intensityID = To Intensity: pitch_floor, time_step, "yes"

# ========================================================================================
# STEP 2: Collect Data
# ========================================================================================

appendInfoLine: "Collecting data..."

selectObject: pitchID
numFrames = Get number of frames

midiMinFound = 1000
midiMaxFound = 0

for i from 1 to numFrames
    selectObject: pitchID
    t_'i' = Get time from frame number: i
    f0_'i' = Get value in frame: i, "Hertz"
    
    f0val = f0_'i'
    if f0val <> undefined
        @hzToMidi: f0val
        midiNote_'i' = hzToMidi.midi
        quantizedMidi_'i' = round(hzToMidi.midi)
        voiced_'i' = 1
        
        if midiNote_'i' < midiMinFound
            midiMinFound = midiNote_'i'
        endif
        if midiNote_'i' > midiMaxFound
            midiMaxFound = midiNote_'i'
        endif
    else
        midiNote_'i' = undefined
        quantizedMidi_'i' = undefined
        voiced_'i' = 0
    endif
    
    selectObject: intensityID
    intensity_'i' = Get value at time: t_'i', "Cubic"
    if intensity_'i' = undefined
        intensity_'i' = intensity_min_db
    endif
endfor

# Set MIDI range
if auto_midi_range and midiMinFound < 1000
    currentMidiMin = floor(midiMinFound) - midi_padding
    currentMidiMax = ceiling(midiMaxFound) + midi_padding
    appendInfoLine: "Auto MIDI range: ", currentMidiMin, " - ", currentMidiMax
else
    currentMidiMin = manual_midi_min
    currentMidiMax = manual_midi_max
    appendInfoLine: "Manual MIDI range: ", currentMidiMin, " - ", currentMidiMax
endif

# ========================================================================================
# STEP 3: Apply Smoothing
# ========================================================================================

if smoothing > 1
    appendInfoLine: "Applying smoothing..."
    
    # Copy to smoothed array
    for i from 1 to numFrames
        smoothedMidi_'i' = midiNote_'i'
    endfor
    
    # Apply filter
    for i from 1 to numFrames
        v = voiced_'i'
        if v = 1
            if smoothing = 2
                @medianFilter3: i
                smoothedMidi_'i' = medianFilter3.result
            elsif smoothing = 3
                @medianFilter5: i
                smoothedMidi_'i' = medianFilter5.result
            elsif smoothing = 4
                @movingAverage: i
                smoothedMidi_'i' = movingAverage.result
            endif
        endif
    endfor
    
    # Copy back
    for i from 1 to numFrames
        v = voiced_'i'
        if v = 1
            midiNote_'i' = smoothedMidi_'i'
        endif
    endfor
endif

# ========================================================================================
# STEP 4: Setup Picture Window
# ========================================================================================

Erase all
Select outer viewport: 0, 10, 0, 6
Font size: 10

# ========================================================================================
# STEP 5: Draw MIDI Grid
# ========================================================================================

appendInfoLine: "Drawing grid..."

Axes: startTime, endTime, currentMidiMin - 0.5, currentMidiMax + 0.5

# Horizontal grid lines
for midiLine from currentMidiMin to currentMidiMax
    @getMidiNoteName: midiLine
    noteClass = midiLine - 12 * floor(midiLine / 12)
    
    drawLine = 0
    
    if noteClass = 0
        Colour: "{0.65, 0.65, 0.65}"
        Line width: 2
        drawLine = 1
    elsif (midiLine mod 12) = 0
        Colour: "{0.75, 0.75, 0.75}"
        Line width: 1.2
        drawLine = 1
    elsif show_all_semitones
        Colour: "{0.92, 0.92, 0.92}"
        Line width: 0.4
        drawLine = 1
    endif
    
    if drawLine = 1
        Draw line: startTime, midiLine, endTime, midiLine
    endif
endfor

# Vertical time grid
if show_time_grid
    Colour: "{0.95, 0.95, 0.95}"
    Line width: 0.3
    
    timeMarker = ceiling(startTime / 0.1) * 0.1
    while timeMarker <= endTime
        Draw line: timeMarker, currentMidiMin - 0.5, timeMarker, currentMidiMax + 0.5
        timeMarker = timeMarker + 0.1
    endwhile
endif

# ========================================================================================
# STEP 6: Draw Note Labels
# ========================================================================================

if show_note_labels
    Font size: 8
    Colour: "{0.5, 0.5, 0.5}"
    
    for midiLine from currentMidiMin to currentMidiMax
        noteClass = midiLine - 12 * floor(midiLine / 12)
        
        if noteClass = 0
            @getMidiNoteName: midiLine
            Text: startTime - duration * 0.02, "right", midiLine, "half", getMidiNoteName.fullName$
        endif
    endfor
    
    Font size: 10
endif

# ========================================================================================
# STEP 7: Draw Pitch Curve
# ========================================================================================

appendInfoLine: "Drawing pitch curve..."

for i from 1 to numFrames - 1
    i1 = i + 1
    v1 = voiced_'i'
    v2 = voiced_'i1'
    
    if v1 = 1 and v2 = 1
        tCurr = t_'i'
        tNext = t_'i1'
        mCurr = midiNote_'i'
        mNext = midiNote_'i1'
        intCurr = intensity_'i'
        
        # Calculate brightness from intensity
        if use_log_loudness
            @logCompress: intCurr, intensity_min_db, intensity_max_db
            brightness = 0.3 + 0.7 * logCompress.result
        else
            @mapToRange: intCurr, intensity_min_db, intensity_max_db, 0.3, 1.0
            brightness = mapToRange.result
        endif
        
        # Choose color scheme
        if color_scheme = 1
            @pitchHeightToRGB: mCurr, brightness
            r = pitchHeightToRGB.red
            g = pitchHeightToRGB.green
            b = pitchHeightToRGB.blue
            
        elsif color_scheme = 2
            @pitchClassToRGB: mCurr, brightness
            r = pitchClassToRGB.red
            g = pitchClassToRGB.green
            b = pitchClassToRGB.blue
            
        elsif color_scheme = 3
            r = brightness
            g = brightness
            b = brightness
            
        elsif color_scheme = 4
            @mapToRange: intCurr, intensity_min_db, intensity_max_db, 0, 1
            heatValue = mapToRange.result
            
            if heatValue < 0.33
                r = 0
                g = heatValue * 3
                b = 1 - heatValue * 3
            elsif heatValue < 0.66
                localVal = (heatValue - 0.33) * 3
                r = localVal
                g = 1
                b = 0
            else
                localVal = (heatValue - 0.66) * 3
                r = 1
                g = 1 - localVal
                b = 0
            endif
            
        elsif color_scheme = 5
            @octaveSpiralRGB: mCurr, brightness
            r = octaveSpiralRGB.red
            g = octaveSpiralRGB.green
            b = octaveSpiralRGB.blue
        endif
        
        colourString$ = "{" + string$(r) + ", " + string$(g) + ", " + string$(b) + "}"
        Colour: colourString$
        
        # Apply line style
        if line_style = 1
            # Thin continuous line
            Line width: 1.5
            Draw line: tCurr, mCurr, tNext, mNext
            
        elsif line_style = 2
            # Thickness varies with loudness
            @mapToRange: intCurr, intensity_min_db, intensity_max_db, 0.5, 4.5
            Line width: mapToRange.result
            Draw line: tCurr, mCurr, tNext, mNext
            
        elsif line_style = 3
            # Dots with size varies with loudness
            @mapToRange: intCurr, intensity_min_db, intensity_max_db, min_dot_size, max_dot_size
            dotSize = mapToRange.result
            Paint circle: colourString$, tCurr, mCurr, dotSize
        endif
    endif
endfor

# ========================================================================================
# STEP 8: Labels
# ========================================================================================

Colour: "Black"
Line width: 1
Font size: 12

Text top: "yes", "Continuous Pitch over MIDI Grid: " + sound$
Text bottom: "yes", "Time (s)"
Text left: "yes", "MIDI Note"

# Get style names for display
if color_scheme = 1
    colorName$ = "Rainbow"
elsif color_scheme = 2
    colorName$ = "PitchClass"
elsif color_scheme = 3
    colorName$ = "Grayscale"
elsif color_scheme = 4
    colorName$ = "Heatmap"
else
    colorName$ = "OctaveSpiral"
endif

if line_style = 1
    styleName$ = "Line"
elsif line_style = 2
    styleName$ = "VaryWidth"
else
    styleName$ = "Dots"
endif

Font size: 8
Select outer viewport: 0, 10, 0, 6
Text: 9.8, "right", currentMidiMax, "top", colorName$
if line_style = 3
    Text: 9.8, "right", currentMidiMax - 2, "top", "Dots: " + fixed$(min_dot_size, 1) + "-" + fixed$(max_dot_size, 1)
else
    Text: 9.8, "right", currentMidiMax - 2, "top", styleName$
endif

# ========================================================================================
# CLEANUP
# ========================================================================================

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Frames: ", numFrames
appendInfoLine: "MIDI range: ", currentMidiMin, " - ", currentMidiMax

removeObject: pitchID, intensityID

selectObject: soundID
Play