# ============================================================
# Praat AudioTools - Melodic_Contour_Parsons_Code.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.0 (2025) - Enhanced visualization & analysis
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Melodic Contour Extraction using Parsons Code with enhanced
#   visualization including graphical contour diagram, contour
#   shape classification, and interval histogram.
#
# Features v2.0:
#   - Parsons Code extraction (* U D R)
#   - Graphical step contour diagram
#   - Contour shape classification (arch, ascending, etc.)
#   - Interval size histogram
#   - Melodic complexity metrics
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
form Melodic Contour - Parsons Code v2.0
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
    boolean Show_visualization 1
    boolean Show_detailed_analysis 1
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
writeInfoLine: "  MELODIC CONTOUR - PARSONS CODE v2.0"
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
    note_interval_st[n] = 0
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
            pitchHz = Get quantile: tStart, tEnd, 0.5, "Hertz"
        elsif pitch_summary = 2
            pitchHz = Get mean: tStart, tEnd, "Hertz"
        else
            pitchHz = Get quantile: tStart, tEnd, 0.5, "Hertz"
        endif
        
        if pitchHz <> undefined and pitchHz > 0
            noteCount += 1
            
            note_start[noteCount] = tStart
            note_end[noteCount] = tEnd
            note_pitch_hz[noteCount] = pitchHz
            
            # Convert Hz to semitones
            pitchST = 69 + 12 * ln(pitchHz / refA4) / ln(2)
            note_pitch_st[noteCount] = pitchST
            
            # Determine Parsons code and interval
            if previousPitchST = undefined
                note_code$[noteCount] = "*"
                note_interval_st[noteCount] = 0
            else
                diff = pitchST - previousPitchST
                note_interval_st[noteCount] = diff
                
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
# STEP 5: PARSONS CODE STATISTICS
# ============================================================

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

# ============================================================
# STEP 6: INTERVAL HISTOGRAM ANALYSIS
# ============================================================

appendInfoLine: "STEP 5: Analyzing intervals..."

# Interval bins: -12 to +12 semitones (and beyond)
maxBins = 25
for b from 1 to maxBins
    intervalBins[b] = 0
endfor

# Bin mapping: bin 13 = unison (0 st), bin 14 = +1 st, bin 12 = -1 st, etc.
centerBin = 13

# Count intervals
for n from 2 to noteCount
    intST = round(note_interval_st[n])
    binIndex = centerBin + intST
    
    if binIndex < 1
        binIndex = 1
    elsif binIndex > maxBins
        binIndex = maxBins
    endif
    
    intervalBins[binIndex] += 1
endfor

# Find max bin count for scaling
maxBinCount = 0
for b from 1 to maxBins
    if intervalBins[b] > maxBinCount
        maxBinCount = intervalBins[b]
    endif
endfor

# Calculate interval statistics
totalIntervalMagnitude = 0
leapCount = 0
stepCount = 0
directionChanges = 0
prevDirection = 0

for n from 2 to noteCount
    absDiff = abs(note_interval_st[n])
    totalIntervalMagnitude += absDiff
    
    if absDiff > 2
        leapCount += 1
    else
        stepCount += 1
    endif
    
    # Track direction changes
    if note_interval_st[n] > threshold_semitones
        currentDirection = 1
    elsif note_interval_st[n] < -threshold_semitones
        currentDirection = -1
    else
        currentDirection = 0
    endif
    
    if prevDirection <> 0 and currentDirection <> 0 and currentDirection <> prevDirection
        directionChanges += 1
    endif
    
    if currentDirection <> 0
        prevDirection = currentDirection
    endif
endfor

avgIntervalSize = totalIntervalMagnitude / (noteCount - 1)

appendInfoLine: "  Leaps (>2 st): ", leapCount
appendInfoLine: "  Steps (≤2 st): ", stepCount
appendInfoLine: "  Direction changes: ", directionChanges
appendInfoLine: "  Average interval: ", fixed$(avgIntervalSize, 2), " st"
appendInfoLine: ""

# ============================================================
# STEP 7: CONTOUR SHAPE CLASSIFICATION
# ============================================================

appendInfoLine: "STEP 6: Classifying contour shape..."

# Calculate contour features
firstPitch = note_pitch_st[1]
lastPitch = note_pitch_st[noteCount]
pitchRange = 0

# Find highest and lowest points
highestPitch = note_pitch_st[1]
lowestPitch = note_pitch_st[1]
highestIndex = 1
lowestIndex = 1

for n from 1 to noteCount
    if note_pitch_st[n] > highestPitch
        highestPitch = note_pitch_st[n]
        highestIndex = n
    endif
    if note_pitch_st[n] < lowestPitch
        lowestPitch = note_pitch_st[n]
        lowestIndex = n
    endif
endfor

pitchRange = highestPitch - lowestPitch

# Calculate first half and second half averages
halfPoint = floor(noteCount / 2)
if halfPoint < 1
    halfPoint = 1
endif

sumFirstHalf = 0
sumSecondHalf = 0

for n from 1 to halfPoint
    sumFirstHalf += note_pitch_st[n]
endfor
avgFirstHalf = sumFirstHalf / halfPoint

for n from halfPoint + 1 to noteCount
    sumSecondHalf += note_pitch_st[n]
endfor
if noteCount - halfPoint > 0
    avgSecondHalf = sumSecondHalf / (noteCount - halfPoint)
else
    avgSecondHalf = avgFirstHalf
endif

# Overall direction
overallDirection = lastPitch - firstPitch

# Classify shape
contourShape$ = "Undefined"
contourDescription$ = ""

# Static (very small range)
if pitchRange < 3
    contourShape$ = "STATIC"
    contourDescription$ = "Little melodic movement, monotone"

# Ascending
elsif overallDirection > pitchRange * 0.5 and countU > countD * 1.5
    contourShape$ = "ASCENDING"
    contourDescription$ = "Overall upward movement"

# Descending
elsif overallDirection < -pitchRange * 0.5 and countD > countU * 1.5
    contourShape$ = "DESCENDING"
    contourDescription$ = "Overall downward movement"

# Arch (convex) - rises then falls, peak in middle
elsif highestIndex > noteCount * 0.25 and highestIndex < noteCount * 0.75 and avgFirstHalf < highestPitch - pitchRange * 0.3 and avgSecondHalf < highestPitch - pitchRange * 0.3
    contourShape$ = "ARCH"
    contourDescription$ = "Rise to peak, then fall (convex)"

# Inverted Arch (concave) - falls then rises, trough in middle  
elsif lowestIndex > noteCount * 0.25 and lowestIndex < noteCount * 0.75 and avgFirstHalf > lowestPitch + pitchRange * 0.3 and avgSecondHalf > lowestPitch + pitchRange * 0.3
    contourShape$ = "INVERTED ARCH"
    contourDescription$ = "Fall to trough, then rise (concave)"

# Wave/Oscillating - many direction changes
elsif directionChanges >= (noteCount - 1) * 0.4
    contourShape$ = "WAVE"
    contourDescription$ = "Oscillating, many direction changes"

# Terraced ascending
elsif countU > countD and countR > (noteCount - 1) * 0.3
    contourShape$ = "TERRACED ASCENDING"
    contourDescription$ = "Stepwise rise with plateaus"

# Terraced descending
elsif countD > countU and countR > (noteCount - 1) * 0.3
    contourShape$ = "TERRACED DESCENDING"
    contourDescription$ = "Stepwise fall with plateaus"

# Balanced
else
    contourShape$ = "BALANCED"
    contourDescription$ = "Mixed movement, no dominant pattern"
endif

# Melodic tendency (simpler)
if countU > countD + 2
    tendency$ = "Generally ASCENDING"
elsif countD > countU + 2
    tendency$ = "Generally DESCENDING"
elsif countR > countU and countR > countD
    tendency$ = "Relatively STATIC"
else
    tendency$ = "BALANCED"
endif

appendInfoLine: "  Shape: ", contourShape$
appendInfoLine: "  Description: ", contourDescription$
appendInfoLine: "  Tendency: ", tendency$
appendInfoLine: "  Range: ", fixed$(pitchRange, 1), " semitones"
appendInfoLine: ""

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
        
        if n > 1
            intervalST = note_interval_st[n]
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
# PARSONS CODE RESULT
# ============================================================

appendInfoLine: "----------------------------------------------"
appendInfoLine: "  PARSONS CODE RESULT"
appendInfoLine: "----------------------------------------------"
appendInfoLine: ""
appendInfoLine: "  ##", parsonsCode$, "##"
appendInfoLine: ""
appendInfoLine: "  Length: ", noteCount, " symbols"
if noteCount > 1
    appendInfoLine: "  Up (U): ", countU, " (", fixed$(countU / (noteCount - 1) * 100, 1), "%)"
    appendInfoLine: "  Down (D): ", countD, " (", fixed$(countD / (noteCount - 1) * 100, 1), "%)"
    appendInfoLine: "  Repeat (R): ", countR, " (", fixed$(countR / (noteCount - 1) * 100, 1), "%)"
endif
appendInfoLine: ""
appendInfoLine: "  Contour Shape: ", contourShape$
appendInfoLine: "  Melodic Tendency: ", tendency$
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
        
        midTime = (note_start[n] + note_end[n]) / 2
        
        interval1 = Get interval at time: 1, midTime
        nocheck Set interval text: 1, interval1, "N" + string$(n)
        
        interval2 = Get interval at time: 2, midTime
        nocheck Set interval text: 2, interval2, note_code$[n]
        
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
    
    # === TITLE ===
    Select outer viewport: 0, 8, 0, 0.7
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.75, "half", "##Melodic Contour - Parsons Code## | " + name$
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.2, "centre", -1., "half", presetName$ + " | Threshold: " + fixed$(threshold_semitones, 1) + " st | Shape: " + contourShape$
    
    # === PANEL 1: GRAPHICAL CONTOUR DIAGRAM (Parsons style) ===
    Select outer viewport: 0, 8, 0.8, 2.8
    Select inner viewport: 0.7, 7.7, 0.9, 2.7
    
    # Axes: note index vs relative pitch level
    Axes: 0, noteCount + 1, -1, 1
    
    # Background
    Paint rectangle: "{0.98, 0.98, 0.99}", 0, noteCount + 1, -1, 1
    
    # Center line (reference)
    Colour: "{0.85, 0.85, 0.88}"
    Line width: 1
    Draw line: 0, 0, noteCount + 1, 0
    
    # Normalize pitches to -1 to +1 range
    midPitch = (highestPitch + lowestPitch) / 2
    if pitchRange > 0
        scaleFactor = 1.8 / pitchRange
    else
        scaleFactor = 1
    endif
    
    # Draw step contour
    Line width: 3
    
    for n from 1 to noteCount
        normalizedPitch = (note_pitch_st[n] - midPitch) * scaleFactor
        
        # Clamp to range
        if normalizedPitch > 0.9
            normalizedPitch = 0.9
        elsif normalizedPitch < -0.9
            normalizedPitch = -0.9
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
        
        # Draw horizontal bar for this note
        Paint rectangle: colour$, n - 0.4, n + 0.4, normalizedPitch - 0.06, normalizedPitch + 0.06
        
        # Draw vertical connection to previous note
        if n > 1
            prevNormalized = (note_pitch_st[n-1] - midPitch) * scaleFactor
            if prevNormalized > 0.9
                prevNormalized = 0.9
            elsif prevNormalized < -0.9
                prevNormalized = -0.9
            endif
            
            Colour: "{0.5, 0.5, 0.6}"
            Line width: 2
            Draw line: n - 0.4, normalizedPitch, n - 0.4, prevNormalized
        endif
        
        # Draw Parsons code below
        Font size: 10
        if note_code$[n] = "U"
            Colour: "{0.2, 0.7, 0.3}"
        elsif note_code$[n] = "D"
            Colour: "{0.8, 0.3, 0.3}"
        elsif note_code$[n] = "R"
            Colour: "{0.6, 0.6, 0.2}"
        else
            Colour: "{0.4, 0.4, 0.8}"
        endif
        Text: n, "centre", -0.85, "half", note_code$[n]
    endfor
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    
    Font size: 7
    Text bottom: "yes", "Note number"
    
    # Label
    Font size: 8
    Select outer viewport: 0, 0.7, 0.8, 2.8
    Axes: 0, 1, 0, 1
    Colour: "{0.3, 0.4, 0.6}"
    Text: 0.9, "right", 0.6, "half", "Contour"
    Font size: 6
    Colour: "{0.5, 0.5, 0.55}"
    Text: 0.9, "right", 0.4, "half", "(step)"
    
    # === PANEL 2: PITCH TIMELINE ===
    Select outer viewport: 0, 8, 2.9, 4.3
    Select inner viewport: 0.7, 7.7, 3.0, 4.2
    
    # Get pitch range for axes
    minPlotPitch = lowestPitch - 2
    maxPlotPitch = highestPitch + 2
    
    Axes: 0, duration, minPlotPitch, maxPlotPitch
    
    # Background
    Paint rectangle: "{0.97, 0.98, 1.0}", 0, duration, minPlotPitch, maxPlotPitch
    
    # Grid lines at semitones
    Colour: "{0.92, 0.92, 0.94}"
    Line width: 0.5
    for st from floor(minPlotPitch) to ceiling(maxPlotPitch)
        Draw line: 0, st, duration, st
    endfor
    
    # Draw note boxes (piano roll style)
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
        
        # Connect to previous
        if n > 1
            prevMid = (note_start[n-1] + note_end[n-1]) / 2
            currMid = (note_start[n] + note_end[n]) / 2
            Colour: "{0.6, 0.6, 0.7}"
            Line width: 1
            Dotted line
            Draw line: prevMid, note_pitch_st[n-1], currMid, pitchST
            Solid line
        endif
    endfor
    
    Colour: "Black"
    Line width: 0.5
    Draw inner box
    
    Font size: 6
    Marks left: 5, "yes", "yes", "no"
    
    Font size: 7
    Select outer viewport: 0, 0.7, 2.9, 4.3
    Axes: 0, 1, 0, 1
    Colour: "{0.3, 0.5, 0.7}"
    Text: 0.9, "right", 0.6, "half", "Pitch"
    Font size: 5
    Colour: "{0.5, 0.5, 0.55}"
    Text: 0.9, "right", 0.35, "half", "(MIDI)"
    
    # === PANEL 3: INTERVAL HISTOGRAM ===
    Select outer viewport: 0, 4, 4.4, 6.2
    Select inner viewport: 0.7, 3.8, 4.5, 6.1
    
    # Show bins from -12 to +12
    histMin = -12
    histMax = 12
    
    if maxBinCount > 0
        Axes: histMin - 0.5, histMax + 0.5, 0, maxBinCount * 1.15
    else
        Axes: histMin - 0.5, histMax + 0.5, 0, 1
    endif
    
    # Background
    Paint rectangle: "{0.98, 0.97, 0.97}", histMin - 0.5, histMax + 0.5, 0, maxBinCount * 1.15
    
    # Zero line
    Colour: "{0.7, 0.7, 0.75}"
    Line width: 1
    Draw line: 0, 0, 0, maxBinCount * 1.1
    
    # Draw bars
    for st from histMin to histMax
        binIndex = centerBin + st
        if binIndex >= 1 and binIndex <= maxBins
            binCount = intervalBins[binIndex]
            
            if binCount > 0
                # Color: green for up, red for down, yellow for unison
                if st > 0
                    colour$ = "{0.3, 0.65, 0.4}"
                elsif st < 0
                    colour$ = "{0.75, 0.4, 0.4}"
                else
                    colour$ = "{0.6, 0.6, 0.3}"
                endif
                
                Paint rectangle: colour$, st - 0.4, st + 0.4, 0, binCount
                
                # Outline
                Colour: "{0.3, 0.3, 0.4}"
                Line width: 0.5
                Draw rectangle: st - 0.4, st + 0.4, 0, binCount
                
                # Count label
                if binCount > 0
                    Font size: 5
                    Colour: "{0.3, 0.3, 0.4}"
                    Text: st, "centre", binCount + maxBinCount * 0.05, "half", string$(binCount)
                endif
            endif
        endif
    endfor
    
    Colour: "Black"
    Line width: 0.5
    Draw inner box
    
    Font size: 5
    Marks bottom every: 1, 3, "yes", "yes", "no"
    
    Font size: 7
    Text bottom: "yes", "Interval (semitones)"
    
    Font size: 7
    Select outer viewport: 0, 0.7, 4.4, 6.2
    Axes: 0, 1, 0, 1
    Colour: "{0.5, 0.4, 0.5}"
    Text: 0.9, "right", 0.6, "half", "Interval"
    Font size: 5
    Colour: "{0.5, 0.5, 0.55}"
    Text: 0.9, "right", 0.35, "half", "histogram"
    
    # === PANEL 4: CONTOUR SHAPE CLASSIFICATION ===
    Select outer viewport: 4, 8, 4.4, 6.2
    Select inner viewport: 4.3, 7.8, 4.5, 6.1
    
    Axes: 0, 1, 0, 1
    
    # Background with shape color
    if contourShape$ = "ASCENDING"
        bgColor$ = "{0.9, 0.95, 0.9}"
        shapeColor$ = "{0.3, 0.7, 0.4}"
    elsif contourShape$ = "DESCENDING"
        bgColor$ = "{0.95, 0.9, 0.9}"
        shapeColor$ = "{0.7, 0.3, 0.3}"
    elsif contourShape$ = "ARCH"
        bgColor$ = "{0.9, 0.92, 0.95}"
        shapeColor$ = "{0.4, 0.5, 0.7}"
    elsif contourShape$ = "INVERTED ARCH"
        bgColor$ = "{0.95, 0.92, 0.9}"
        shapeColor$ = "{0.7, 0.5, 0.4}"
    elsif contourShape$ = "WAVE"
        bgColor$ = "{0.92, 0.92, 0.95}"
        shapeColor$ = "{0.5, 0.5, 0.7}"
    elsif contourShape$ = "STATIC"
        bgColor$ = "{0.94, 0.94, 0.92}"
        shapeColor$ = "{0.6, 0.6, 0.4}"
    else
        bgColor$ = "{0.94, 0.94, 0.94}"
        shapeColor$ = "{0.5, 0.5, 0.5}"
    endif
    
    Paint rectangle: bgColor$, 0, 1, 0, 1
    
    # Draw shape icon
    Colour: shapeColor$
    Line width: 3
    
    if contourShape$ = "ASCENDING"
        Draw line: 0.15, 0.3, 0.85, 0.7
    elsif contourShape$ = "DESCENDING"
        Draw line: 0.15, 0.7, 0.85, 0.3
    elsif contourShape$ = "ARCH"
        # Draw arch curve
        for i from 0 to 20
            x1 = 0.15 + (i / 20) * 0.7
            x2 = 0.15 + ((i + 1) / 20) * 0.7
            y1 = 0.3 + 0.4 * sin((i / 20) * pi)
            y2 = 0.3 + 0.4 * sin(((i + 1) / 20) * pi)
            Draw line: x1, y1, x2, y2
        endfor
    elsif contourShape$ = "INVERTED ARCH"
        for i from 0 to 20
            x1 = 0.15 + (i / 20) * 0.7
            x2 = 0.15 + ((i + 1) / 20) * 0.7
            y1 = 0.7 - 0.4 * sin((i / 20) * pi)
            y2 = 0.7 - 0.4 * sin(((i + 1) / 20) * pi)
            Draw line: x1, y1, x2, y2
        endfor
    elsif contourShape$ = "WAVE"
        for i from 0 to 20
            x1 = 0.15 + (i / 20) * 0.7
            x2 = 0.15 + ((i + 1) / 20) * 0.7
            y1 = 0.5 + 0.2 * sin((i / 20) * 3 * pi)
            y2 = 0.5 + 0.2 * sin(((i + 1) / 20) * 3 * pi)
            Draw line: x1, y1, x2, y2
        endfor
    elsif contourShape$ = "STATIC"
        Draw line: 0.15, 0.5, 0.85, 0.5
    elsif contourShape$ = "TERRACED ASCENDING"
        Draw line: 0.15, 0.35, 0.35, 0.35
        Draw line: 0.35, 0.35, 0.35, 0.5
        Draw line: 0.35, 0.5, 0.55, 0.5
        Draw line: 0.55, 0.5, 0.55, 0.65
        Draw line: 0.55, 0.65, 0.85, 0.65
    elsif contourShape$ = "TERRACED DESCENDING"
        Draw line: 0.15, 0.65, 0.35, 0.65
        Draw line: 0.35, 0.65, 0.35, 0.5
        Draw line: 0.35, 0.5, 0.55, 0.5
        Draw line: 0.55, 0.5, 0.55, 0.35
        Draw line: 0.55, 0.35, 0.85, 0.35
    else
        # Balanced - zigzag
        Draw line: 0.15, 0.5, 0.35, 0.65
        Draw line: 0.35, 0.65, 0.5, 0.4
        Draw line: 0.5, 0.4, 0.65, 0.6
        Draw line: 0.65, 0.6, 0.85, 0.5
    endif
    
    Line width: 1
    
    # Shape name
    Font size: 10
    Colour: shapeColor$
    Text: 0.5, "centre", 0.12, "half", contourShape$
    
    Colour: "Black"
    Line width: 0.5
    Draw inner box
    
    # === PANEL 5: LEGEND & STATISTICS ===
    Select outer viewport: 0, 8, 6.3, 7.2
    Axes: 0, 1, 0, 1
    
    Font size: 7
    
    # Parsons code legend
    Colour: "{0.4, 0.4, 0.8}"
    Text: 0.02, "left", 0.75, "half", "* First"
    
    Paint rectangle: "{0.2, 0.7, 0.3}", 0.09, 0.11, 0.65, 0.85
    Colour: "Black"
    Text: 0.12, "left", 0.75, "half", "U Up (" + string$(countU) + ")"
    
    Paint rectangle: "{0.8, 0.3, 0.3}", 0.22, 0.24, 0.65, 0.85
    Colour: "Black"
    Text: 0.25, "left", 0.75, "half", "D Down (" + string$(countD) + ")"
    
    Paint rectangle: "{0.6, 0.6, 0.2}", 0.36, 0.38, 0.65, 0.85
    Colour: "Black"
    Text: 0.39, "left", 0.75, "half", "R Repeat (" + string$(countR) + ")"
    
    # Statistics
    Font size: 6
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.02, "left", 0.35, "half", "Notes: " + string$(noteCount)
    Text: 0.12, "left", 0.35, "half", "Range: " + fixed$(pitchRange, 1) + " st"
    Text: 0.26, "left", 0.35, "half", "Leaps: " + string$(leapCount)
    Text: 0.36, "left", 0.35, "half", "Steps: " + string$(stepCount)
    Text: 0.46, "left", 0.35, "half", "Dir.chg: " + string$(directionChanges)
    Text: 0.58, "left", 0.35, "half", "Avg.int: " + fixed$(avgIntervalSize, 1) + " st"
    
    # Parsons code (truncated if long)
    Font size: 6
    Colour: "{0.2, 0.2, 0.3}"
    if length(parsonsCode$) <= 30
        Text: 0.55, "left", 0.75, "half", "Code: " + parsonsCode$
    else
        Text: 0.55, "left", 0.75, "half", "Code: " + left$(parsonsCode$, 27) + "..."
    endif
    
    Font size: 10
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
appendInfoLine: "  CONTOUR SHAPE: ", contourShape$
appendInfoLine: "  ", contourDescription$
appendInfoLine: ""
appendInfoLine: "  Use this code to search melodic databases"
appendInfoLine: "  or compare with other melodies."
appendInfoLine: ""

if create_TextGrid_output
    selectObject: outputTG
endif

appendInfoLine: "Done!"