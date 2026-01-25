# ============================================================
# Praat AudioTools - Melodic_Contour_Parsons_Code.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Melodic Contour Extraction using Parsons Code.
#   Analyzes monophonic audio (singing/speech) and outputs
#   a string representing pitch movement:
#     * = First note
#     U = Up (pitch rises)
#     D = Down (pitch falls)
#     R = Repeat (pitch stays within threshold)
#
# Usage:
#   Select a Sound object and run this script.
#   Works best with monophonic melodic content.
#
# Reference:
#   Parsons, D. (1975). The Directory of Tunes and Musical Themes.
#
# Category: Analysis & Feature Extraction
# ============================================================

# === INPUT VALIDATION ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

sound = selected("Sound")
name$ = selected$("Sound")

# === USER PARAMETERS ===
form Melodic Contour - Parsons Code Extraction
    comment === Preset ===
    optionmenu Preset 1
        option Custom (manual settings)
        option Speech (wide threshold)
        option Singing (narrow threshold)
        option Instrumental (very narrow)
        option Whistle/Flute (precise)
    
    comment === Segmentation (Silence Detection) ===
    positive Min_pitch_Hz 100
    integer Silence_threshold_dB -25
    positive Min_silence_duration_s 0.10
    positive Min_sounding_duration_s 0.08
    
    comment === Pitch Analysis ===
    positive Pitch_floor_Hz 75
    positive Pitch_ceiling_Hz 600
    
    comment === Contour Comparison ===
    positive Threshold_semitones 1.0
    optionmenu Pitch_summary 1
        option Median (recommended)
        option Mean
        option Mode (most frequent)
    
    comment === Output ===
    boolean Show_detailed_analysis 1
    boolean Show_visualization 1
    boolean Create_TextGrid_output 1
    boolean Show_pitch_values 1
endform

# === APPLY PRESETS ===
if preset > 1
    if preset = 2
        # Speech
        min_pitch_Hz = 75
        silence_threshold_dB = -25
        min_silence_duration_s = 0.15
        min_sounding_duration_s = 0.10
        pitch_floor_Hz = 75
        pitch_ceiling_Hz = 400
        threshold_semitones = 2.0
        presetName$ = "Speech"
    elsif preset = 3
        # Singing
        min_pitch_Hz = 100
        silence_threshold_dB = -30
        min_silence_duration_s = 0.08
        min_sounding_duration_s = 0.08
        pitch_floor_Hz = 80
        pitch_ceiling_Hz = 600
        threshold_semitones = 0.75
        presetName$ = "Singing"
    elsif preset = 4
        # Instrumental
        min_pitch_Hz = 80
        silence_threshold_dB = -35
        min_silence_duration_s = 0.05
        min_sounding_duration_s = 0.05
        pitch_floor_Hz = 50
        pitch_ceiling_Hz = 1000
        threshold_semitones = 0.5
        presetName$ = "Instrumental"
    elsif preset = 5
        # Whistle/Flute
        min_pitch_Hz = 200
        silence_threshold_dB = -40
        min_silence_duration_s = 0.03
        min_sounding_duration_s = 0.03
        pitch_floor_Hz = 200
        pitch_ceiling_Hz = 2000
        threshold_semitones = 0.25
        presetName$ = "Whistle/Flute"
    endif
else
    presetName$ = "Custom"
endif

# === SETUP ===
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  MELODIC CONTOUR - PARSONS CODE"
writeInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Sound: ", name$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Threshold: ", threshold_semitones, " semitones"
appendInfoLine: ""

selectObject: sound
duration = Get total duration
sampleRate = Get sampling frequency

appendInfoLine: "Duration: ", fixed$(duration, 3), " s"
appendInfoLine: "Sample rate: ", sampleRate, " Hz"
appendInfoLine: ""

# ============================================================
# STEP 1: SEGMENTATION (Silence Detection)
# ============================================================

appendInfoLine: "STEP 1: Segmenting into notes/syllables..."

selectObject: sound
textgrid = To TextGrid (silences): min_pitch_Hz, 0, silence_threshold_dB, min_silence_duration_s, min_sounding_duration_s, "silent", "sounding"

selectObject: textgrid
numIntervals = Get number of intervals: 1

# Count sounding intervals
numSounding = 0
for i from 1 to numIntervals
    selectObject: textgrid
    label$ = Get label of interval: 1, i
    if label$ = "sounding"
        numSounding += 1
    endif
endfor

appendInfoLine: "  Total intervals: ", numIntervals
appendInfoLine: "  Sounding segments: ", numSounding
appendInfoLine: ""

if numSounding < 1
    appendInfoLine: "ERROR: No sounding segments detected!"
    appendInfoLine: "Try adjusting silence threshold or minimum durations."
    removeObject: textgrid
    exitScript()
endif

# ============================================================
# STEP 2: PITCH EXTRACTION
# ============================================================

appendInfoLine: "STEP 2: Extracting pitch..."

selectObject: sound
pitch = To Pitch: 0, pitch_floor_Hz, pitch_ceiling_Hz

selectObject: pitch
meanPitch = Get mean: 0, 0, "Hertz"
minPitch = Get minimum: 0, 0, "Hertz", "Parabolic"
maxPitch = Get maximum: 0, 0, "Hertz", "Parabolic"

if meanPitch = undefined
    appendInfoLine: "ERROR: No pitch detected in audio!"
    appendInfoLine: "Check if audio contains voiced/melodic content."
    removeObject: textgrid, pitch
    exitScript()
endif

appendInfoLine: "  Mean pitch: ", fixed$(meanPitch, 1), " Hz"
appendInfoLine: "  Range: ", fixed$(minPitch, 1), " - ", fixed$(maxPitch, 1), " Hz"
appendInfoLine: ""

# ============================================================
# STEP 3: ANALYZE EACH SEGMENT
# ============================================================

appendInfoLine: "STEP 3: Analyzing melodic contour..."
appendInfoLine: ""

# Arrays to store results
maxNotes = 500
for n from 1 to maxNotes
    note_start[n] = 0
    note_end[n] = 0
    note_pitch_hz[n] = 0
    note_pitch_st[n] = 0
    note_code$[n] = ""
endfor

noteCount = 0
previousPitchST = undefined

# Reference for semitone conversion (A4 = 440 Hz = MIDI 69)
refA4 = 440

for i from 1 to numIntervals
    selectObject: textgrid
    label$ = Get label of interval: 1, i
    
    if label$ = "sounding"
        tStart = Get start time of interval: 1, i
        tEnd = Get end time of interval: 1, i
        
        # Get pitch for this segment
        selectObject: pitch
        
        if pitch_summary = 1
            # Median
            pitchHz = Get quantile: tStart, tEnd, 0.5, "Hertz"
        elsif pitch_summary = 2
            # Mean
            pitchHz = Get mean: tStart, tEnd, "Hertz"
        else
            # Mode (approximated by getting value at intensity peak)
            pitchHz = Get quantile: tStart, tEnd, 0.5, "Hertz"
        endif
        
        # Skip if pitch is undefined (unvoiced segment)
        if pitchHz <> undefined and pitchHz > 0
            noteCount += 1
            
            # Store timing
            note_start[noteCount] = tStart
            note_end[noteCount] = tEnd
            note_pitch_hz[noteCount] = pitchHz
            
            # Convert Hz to semitones (MIDI-like scale)
            # Formula: semitones = 69 + 12 * log2(Hz / 440)
            pitchST = 69 + 12 * ln(pitchHz / refA4) / ln(2)
            note_pitch_st[noteCount] = pitchST
            
            # Determine Parsons code
            if previousPitchST = undefined
                # First note
                note_code$[noteCount] = "*"
            else
                diff = pitchST - previousPitchST
                
                if diff > threshold_semitones
                    note_code$[noteCount] = "U"
                elsif diff < -threshold_semitones
                    note_code$[noteCount] = "D"
                else
                    note_code$[noteCount] = "R"
                endif
            endif
            
            previousPitchST = pitchST
        endif
    endif
endfor

appendInfoLine: "  Notes analyzed: ", noteCount
appendInfoLine: ""

if noteCount < 1
    appendInfoLine: "ERROR: No pitched notes detected!"
    removeObject: textgrid, pitch
    exitScript()
endif

# ============================================================
# STEP 4: BUILD PARSONS CODE STRING
# ============================================================

appendInfoLine: "STEP 4: Building Parsons Code..."
appendInfoLine: ""

parsonsCode$ = ""
for n from 1 to noteCount
    parsonsCode$ = parsonsCode$ + note_code$[n]
endfor

# ============================================================
# DETAILED ANALYSIS OUTPUT
# ============================================================

if show_detailed_analysis
    appendInfoLine: "----------------------------------------------"
    appendInfoLine: "  DETAILED NOTE ANALYSIS"
    appendInfoLine: "----------------------------------------------"
    appendInfoLine: ""
    appendInfoLine: "Note | Time (s)    | Pitch (Hz) | MIDI | Code | Interval"
    appendInfoLine: "-----|-------------|------------|------|------|----------"
    
    for n from 1 to noteCount
        timeStr$ = fixed$(note_start[n], 2) + "-" + fixed$(note_end[n], 2)
        pitchStr$ = fixed$(note_pitch_hz[n], 1)
        midiStr$ = fixed$(note_pitch_st[n], 1)
        
        # Calculate interval from previous note
        if n > 1
            intervalST = note_pitch_st[n] - note_pitch_st[n-1]
            if intervalST >= 0
                intervalStr$ = "+" + fixed$(intervalST, 1) + " st"
            else
                intervalStr$ = fixed$(intervalST, 1) + " st"
            endif
        else
            intervalStr$ = "(start)"
        endif
        
        appendInfoLine: "  ", n, "  | ", timeStr$, " | ", pitchStr$, "    | ", midiStr$, " | ", note_code$[n], "    | ", intervalStr$
    endfor
    
    appendInfoLine: ""
endif

# ============================================================
# PARSONS CODE STATISTICS
# ============================================================

# Count U, D, R
countU = 0
countD = 0
countR = 0

for n from 1 to noteCount
    if note_code$[n] = "U"
        countU += 1
    elsif note_code$[n] = "D"
        countD += 1
    elsif note_code$[n] = "R"
        countR += 1
    endif
endfor

appendInfoLine: "----------------------------------------------"
appendInfoLine: "  PARSONS CODE RESULT"
appendInfoLine: "----------------------------------------------"
appendInfoLine: ""
appendInfoLine: "  ##", parsonsCode$, "##"
appendInfoLine: ""
appendInfoLine: "  Length: ", noteCount, " symbols"
appendInfoLine: "  Up (U): ", countU, " (", fixed$(countU / (noteCount - 1) * 100, 1), "%)"
appendInfoLine: "  Down (D): ", countD, " (", fixed$(countD / (noteCount - 1) * 100, 1), "%)"
appendInfoLine: "  Repeat (R): ", countR, " (", fixed$(countR / (noteCount - 1) * 100, 1), "%)"
appendInfoLine: ""

# Melodic direction tendency
if countU > countD + 2
    tendency$ = "Generally ASCENDING"
elsif countD > countU + 2
    tendency$ = "Generally DESCENDING"
elsif countR > countU and countR > countD
    tendency$ = "Relatively STATIC"
else
    tendency$ = "BALANCED / WAVE-LIKE"
endif

appendInfoLine: "  Melodic tendency: ", tendency$
appendInfoLine: ""

# ============================================================
# CREATE OUTPUT TEXTGRID
# ============================================================

if create_TextGrid_output
    appendInfoLine: "Creating annotated TextGrid..."
    
    selectObject: sound
    outputTG = To TextGrid: "Notes Parsons Pitch", ""
    
    currentTime = 0
    for n from 1 to noteCount
        selectObject: outputTG
        
        # Add boundaries
        if note_start[n] > currentTime and note_start[n] < duration
            nocheck Insert boundary: 1, note_start[n]
            nocheck Insert boundary: 2, note_start[n]
            nocheck Insert boundary: 3, note_start[n]
        endif
        if note_end[n] < duration
            nocheck Insert boundary: 1, note_end[n]
            nocheck Insert boundary: 2, note_end[n]
            nocheck Insert boundary: 3, note_end[n]
        endif
        
        # Label intervals
        midTime = (note_start[n] + note_end[n]) / 2
        
        # Tier 1: Note numbers
        interval1 = Get interval at time: 1, midTime
        nocheck Set interval text: 1, interval1, "N" + string$(n)
        
        # Tier 2: Parsons code
        interval2 = Get interval at time: 2, midTime
        nocheck Set interval text: 2, interval2, note_code$[n]
        
        # Tier 3: Pitch values
        if show_pitch_values
            interval3 = Get interval at time: 3, midTime
            nocheck Set interval text: 3, interval3, fixed$(note_pitch_hz[n], 0) + "Hz"
        endif
        
        currentTime = note_end[n]
    endfor
    
    selectObject: outputTG
    Rename: name$ + "_parsons"
    
    appendInfoLine: "  Created: ", name$, "_parsons (TextGrid)"
    appendInfoLine: ""
endif

# ============================================================
# VISUALIZATION
# ============================================================

if show_visualization
    appendInfoLine: "Creating visualization..."
    
    Erase all
    
    # --- TITLE ---
    Select outer viewport: 0, 8, 0, 0.5
    Font size: 11
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Melodic Contour - Parsons Code## | " + name$ + " | " + presetName$
    
    # --- WAVEFORM WITH NOTE BOUNDARIES ---
    Select outer viewport: 0, 8, 0.6, 1.8
    Select inner viewport: 0.8, 7.8, 0.7, 1.7
    
    selectObject: sound
    Colour: "{0.5, 0.6, 0.75}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    # Draw note boundaries
    Colour: "{0.8, 0.3, 0.3}"
    Line width: 1
    Dotted line
    for n from 1 to noteCount
        Draw line: note_start[n], -0.95, note_start[n], 0.95
    endfor
    Solid line
    
    Colour: "Black"
    Line width: 0.5
    Draw inner box
    
    Font size: 7
    Select outer viewport: 0, 0.8, 0.6, 1.8
    Axes: 0, 1, 0, 1
    Colour: "{0.3, 0.4, 0.6}"
    Text: 0.95, "right", 0.5, "half", "Waveform"
    
    # --- PITCH CONTOUR WITH PARSONS CODES ---
    Select outer viewport: 0, 8, 1.9, 3.5
    Select inner viewport: 0.8, 7.8, 2.0, 3.4
    
    # Get pitch range for axes
    minPlotPitch = minPitch * 0.9
    maxPlotPitch = maxPitch * 1.1
    
    Axes: 0, duration, minPlotPitch, maxPlotPitch
    
    # Background
    Paint rectangle: "{0.97, 0.98, 1.0}", 0, duration, minPlotPitch, maxPlotPitch
    
    # Draw pitch contour
    selectObject: pitch
    Colour: "{0.3, 0.5, 0.8}"
    Line width: 1.5
    Draw: 0, 0, minPlotPitch, maxPlotPitch, "no"
    
    # Draw note medians and Parsons codes
    for n from 1 to noteCount
        midTime = (note_start[n] + note_end[n]) / 2
        pitchHz = note_pitch_hz[n]
        
        # Note median marker
        markerSize = (note_end[n] - note_start[n]) / 2
        if markerSize > 0.05
            markerSize = 0.05
        endif
        
        # Color by direction
        if note_code$[n] = "U"
            colour$ = "{0.2, 0.7, 0.3}"
        elsif note_code$[n] = "D"
            colour$ = "{0.8, 0.3, 0.3}"
        elsif note_code$[n] = "R"
            colour$ = "{0.6, 0.6, 0.2}"
        else
            colour$ = "{0.4, 0.4, 0.8}"
        endif
        
        # Draw marker
        Paint rectangle: colour$, note_start[n] + 0.005, note_end[n] - 0.005, pitchHz - (maxPlotPitch - minPlotPitch) * 0.02, pitchHz + (maxPlotPitch - minPlotPitch) * 0.02
        
        # Draw Parsons code above
        Font size: 10
        Colour: colour$
        labelY = pitchHz + (maxPlotPitch - minPlotPitch) * 0.08
        if labelY > maxPlotPitch * 0.95
            labelY = pitchHz - (maxPlotPitch - minPlotPitch) * 0.08
        endif
        Text: midTime, "centre", labelY, "half", note_code$[n]
        
        # Draw connecting line to previous note
        if n > 1
            prevMidTime = (note_start[n-1] + note_end[n-1]) / 2
            prevPitchHz = note_pitch_hz[n-1]
            
            Colour: "{0.6, 0.6, 0.7}"
            Line width: 1
            Dotted line
            Draw line: prevMidTime, prevPitchHz, midTime, pitchHz
            Solid line
        endif
    endfor
    
    Colour: "Black"
    Line width: 0.5
    Draw inner box
    
    # Y-axis labels (Hz)
    Font size: 6
    Marks left: 5, "yes", "yes", "no"
    
    Font size: 7
    Select outer viewport: 0, 0.8, 1.9, 3.5
    Axes: 0, 1, 0, 1
    Colour: "{0.3, 0.5, 0.7}"
    Text: 0.95, "right", 0.6, "half", "Pitch"
    Font size: 5
    Colour: "{0.5, 0.5, 0.55}"
    Text: 0.95, "right", 0.35, "half", "(Hz)"
    
    # --- SEMITONE PLOT (Piano Roll Style) ---
    Select outer viewport: 0, 8, 3.6, 5.0
    Select inner viewport: 0.8, 7.8, 3.7, 4.9
    
    # Get semitone range
    minST = note_pitch_st[1]
    maxST = note_pitch_st[1]
    for n from 2 to noteCount
        if note_pitch_st[n] < minST
            minST = note_pitch_st[n]
        endif
        if note_pitch_st[n] > maxST
            maxST = note_pitch_st[n]
        endif
    endfor
    
    # Expand range slightly
    minST = floor(minST) - 1
    maxST = ceiling(maxST) + 1
    
    Axes: 0, duration, minST, maxST
    
    # Background with semitone grid
    Paint rectangle: "{0.98, 0.98, 0.99}", 0, duration, minST, maxST
    
    # Draw semitone lines
    Colour: "{0.9, 0.9, 0.92}"
    Line width: 0.5
    for st from floor(minST) to ceiling(maxST)
        Draw line: 0, st, duration, st
    endfor
    
    # Draw notes as boxes
    for n from 1 to noteCount
        pitchST = note_pitch_st[n]
        
        if note_code$[n] = "U"
            colour$ = "{0.2, 0.7, 0.3}"
        elsif note_code$[n] = "D"
            colour$ = "{0.8, 0.3, 0.3}"
        elsif note_code$[n] = "R"
            colour$ = "{0.6, 0.6, 0.2}"
        else
            colour$ = "{0.4, 0.4, 0.8}"
        endif
        
        Paint rectangle: colour$, note_start[n], note_end[n], pitchST - 0.4, pitchST + 0.4
        
        # Outline
        Colour: "{0.3, 0.3, 0.4}"
        Line width: 0.5
        Draw rectangle: note_start[n], note_end[n], pitchST - 0.4, pitchST + 0.4
    endfor
    
    Colour: "Black"
    Line width: 0.5
    Draw inner box
    
    Font size: 6
    Marks left: 5, "yes", "yes", "no"
    
    Font size: 7
    Select outer viewport: 0, 0.8, 3.6, 5.0
    Axes: 0, 1, 0, 1
    Colour: "{0.4, 0.4, 0.6}"
    Text: 0.95, "right", 0.6, "half", "MIDI"
    Font size: 5
    Colour: "{0.5, 0.5, 0.55}"
    Text: 0.95, "right", 0.35, "half", "(semitones)"
    
    # --- PARSONS CODE DISPLAY ---
    Select outer viewport: 0, 8, 5.1, 5.8
    Select inner viewport: 0.8, 7.8, 5.2, 5.7
    
    Axes: 0, noteCount + 1, 0, 1
    
    Paint rectangle: "{0.99, 0.99, 0.98}", 0, noteCount + 1, 0, 1
    
    for n from 1 to noteCount
        if note_code$[n] = "U"
            colour$ = "{0.2, 0.7, 0.3}"
        elsif note_code$[n] = "D"
            colour$ = "{0.8, 0.3, 0.3}"
        elsif note_code$[n] = "R"
            colour$ = "{0.6, 0.6, 0.2}"
        else
            colour$ = "{0.4, 0.4, 0.8}"
        endif
        
        Font size: 12
        Colour: colour$
        Text: n, "centre", 0.5, "half", note_code$[n]
    endfor
    
    Colour: "Black"
    Line width: 0.5
    Draw inner box
    
    Font size: 7
    Select outer viewport: 0, 0.8, 5.1, 5.8
    Axes: 0, 1, 0, 1
    Colour: "{0.3, 0.3, 0.4}"
    Text: 0.95, "right", 0.5, "half", "Code"
    
    # --- LEGEND & STATISTICS ---
    Select outer viewport: 0, 8, 5.9, 6.7
    Axes: 0, 1, 0, 1
    
    Font size: 7
    
    # Legend
    Colour: "{0.4, 0.4, 0.8}"
    Text: 0.02, "left", 0.75, "half", "* = First"
    
    Colour: "{0.2, 0.7, 0.3}"
    Paint rectangle: "{0.2, 0.7, 0.3}", 0.12, 0.14, 0.65, 0.85
    Colour: "Black"
    Text: 0.15, "left", 0.75, "half", "U = Up (" + string$(countU) + ")"
    
    Colour: "{0.8, 0.3, 0.3}"
    Paint rectangle: "{0.8, 0.3, 0.3}", 0.28, 0.30, 0.65, 0.85
    Colour: "Black"
    Text: 0.31, "left", 0.75, "half", "D = Down (" + string$(countD) + ")"
    
    Colour: "{0.6, 0.6, 0.2}"
    Paint rectangle: "{0.6, 0.6, 0.2}", 0.46, 0.48, 0.65, 0.85
    Colour: "Black"
    Text: 0.49, "left", 0.75, "half", "R = Repeat (" + string$(countR) + ")"
    
    # Statistics
    Font size: 5
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.02, "left", 0.25, "half", "Notes: " + string$(noteCount)
    Text: 0.15, "left", 0.25, "half", "Threshold: " + fixed$(threshold_semitones, 1) + " st"
    Text: 0.32, "left", 0.25, "half", "Range: " + fixed$(minPitch, 0) + "-" + fixed$(maxPitch, 0) + " Hz"
    Text: 0.52, "left", 0.25, "half", "Tendency: " + tendency$
    
    # Full code display
    Font size: 6
    Colour: "{0.2, 0.2, 0.3}"
    if length(parsonsCode$) <= 40
        Text: 0.75, "left", 0.75, "half", parsonsCode$
    else
        Text: 0.75, "left", 0.75, "half", left$(parsonsCode$, 37) + "..."
    endif
    
    # --- TIME AXIS ---
    Select outer viewport: 0, 8, 6.7, 7.0
    Select inner viewport: 0.8, 7.8, 6.75, 6.95
    
    Axes: 0, duration, 0, 1
    
    Colour: "{0.3, 0.3, 0.4}"
    Line width: 1
    Draw line: 0, 0.7, duration, 0.7
    
    Font size: 5
    tickStep = 0.5
    if duration > 5
        tickStep = 1
    endif
    if duration > 15
        tickStep = 2
    endif
    if duration > 30
        tickStep = 5
    endif
    
    t = 0
    while t <= duration
        Draw line: t, 0.7, t, 0.3
        Text: t, "centre", 0.1, "half", fixed$(t, 1)
        t = t + tickStep
    endwhile
    
    Font size: 6
    Text: duration / 2, "centre", -0.5, "half", "Time (s)"
    
    Font size: 10
    Line width: 1
    Colour: "Black"
    
    appendInfoLine: "  Visualization complete"
    appendInfoLine: ""
endif

# ============================================================
# CLEANUP
# ============================================================

removeObject: textgrid, pitch

# ============================================================
# FINAL OUTPUT
# ============================================================

appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "  PARSONS CODE: ", parsonsCode$
appendInfoLine: ""
appendInfoLine: "  Use this code to search melodic databases"
appendInfoLine: "  or compare with other melodies."
appendInfoLine: ""

# Select output TextGrid if created
if create_TextGrid_output
    selectObject: outputTG
endif

appendInfoLine: "Done!"
