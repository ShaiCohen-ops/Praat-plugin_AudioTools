# ============================================================
# Praat AudioTools - Formant to MIDI Chord Converter with Visualizations
# Author: Shai Cohen 
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025) - Added cent deviation visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Formant to MIDI Chord Converter with Visual Analysis
#   - Extracts formants and converts to MIDI chords
#   - Creates formant trajectory plots over time
#   - Generates MIDI piano roll visualization
#   - Shows spectral formant positions
#   - Displays chord progression analysis
#   - Visualizes cent deviations from pure MIDI notes
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# Check if a Sound object is selected
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

# Get the selected Sound
sound = selected("Sound")
soundName$ = selected$("Sound")

# Parameters
form Formant Analysis Parameters
    comment === Analysis Parameters ===
    positive Number_of_segments 8
    positive Time_step 0.01
    positive Max_formant_Hz 5500
    positive Number_of_formants 5
    positive Window_length 0.025
    comment === Visualization Options ===
    boolean Show_formant_trajectories 0
    boolean Show_MIDI_piano_roll 0
    boolean Show_spectral_analysis 0
    boolean Show_chord_progression 0
    boolean Show_cent_deviations 0
endform

# Clear info window
clearinfo

# Get sound duration
selectObject: sound
duration = Get total duration
segmentDuration = duration / number_of_segments

# Print header
appendInfoLine: "=== Formant to MIDI Chord Analysis ==="
appendInfoLine: "Sound: ", soundName$
appendInfoLine: "Duration: ", fixed$(duration, 3), " seconds"
appendInfoLine: "Segments: ", number_of_segments
appendInfoLine: "Segment duration: ", fixed$(segmentDuration, 3), " seconds"
appendInfoLine: ""

# Create Formant object
selectObject: sound
formant = To Formant (burg): time_step, number_of_formants, max_formant_Hz, window_length, 50

# Arrays to store data for visualizations
# Create Table to store formant and MIDI data
dataTable = Create Table with column names: "analysisData", number_of_segments,
    ... "segment time F1_Hz F2_Hz F3_Hz F4_Hz F1_MIDI F2_MIDI F3_MIDI F4_MIDI F1_note F2_note F3_note F4_note F1_cents F2_cents F3_cents F4_cents"

# Function to convert frequency (Hz) to MIDI cent
procedure freqToMidiCent: freq
    if freq > 0
        # MIDI note number = 69 + 12 * log2(freq/440)
        # MIDI cent = MIDI note * 100
        midiNote = 69 + 12 * ln(freq/440) / ln(2)
        .midiCent = midiNote * 100
        .midiNote = midiNote
    else
        .midiCent = 0
        .midiNote = 0
    endif
endproc

# Function to get note name from MIDI note
procedure getNoteNameFromMIDI: midiNote
    noteNum = round(midiNote)
    octave = floor((noteNum - 12) / 12)
    pitchClass = (noteNum - 12) mod 12
    
    # Note names
    if pitchClass = 0
        noteName$ = "C"
    elsif pitchClass = 1
        noteName$ = "C#"
    elsif pitchClass = 2
        noteName$ = "D"
    elsif pitchClass = 3
        noteName$ = "D#"
    elsif pitchClass = 4
        noteName$ = "E"
    elsif pitchClass = 5
        noteName$ = "F"
    elsif pitchClass = 6
        noteName$ = "F#"
    elsif pitchClass = 7
        noteName$ = "G"
    elsif pitchClass = 8
        noteName$ = "G#"
    elsif pitchClass = 9
        noteName$ = "A"
    elsif pitchClass = 10
        noteName$ = "A#"
    elsif pitchClass = 11
        noteName$ = "B"
    endif
    
    .noteName$ = noteName$ + string$(octave)
endproc

# Analyze each segment and store data
for segment from 1 to number_of_segments
    # Calculate time point at center of segment
    startTime = (segment - 1) * segmentDuration
    endTime = segment * segmentDuration
    midTime = (startTime + endTime) / 2
    
    appendInfoLine: "--- Segment ", segment, " ---"
    appendInfoLine: "Time range: ", fixed$(startTime, 3), " - ", fixed$(endTime, 3), " s"
    appendInfoLine: "Analysis point: ", fixed$(midTime, 3), " s"
    
    # Store segment and time
    selectObject: dataTable
    Set numeric value: segment, "segment", segment
    Set numeric value: segment, "time", midTime
    
    appendInfoLine: "Chord (4-part harmony):"
    
    # Get formants F1-F4 and convert to MIDI cents
    for formantNum from 1 to 4
        # Make sure formant object is selected
        selectObject: formant
        freq = Get value at time: formantNum, midTime, "Hertz", "Linear"
        
        if freq <> undefined and freq > 0
            call freqToMidiCent freq
            midiCent = freqToMidiCent.midiCent
            midiNote = freqToMidiCent.midiNote
            
            # Calculate cent deviation
            noteNum = round(midiNote)
            cents_deviation = round((midiCent - noteNum * 100))
            
            # Store in table
            selectObject: dataTable
            Set numeric value: segment, "F" + string$(formantNum) + "_Hz", freq
            Set numeric value: segment, "F" + string$(formantNum) + "_MIDI", midiNote
            Set numeric value: segment, "F" + string$(formantNum) + "_cents", cents_deviation
            
            # Get note name
            call getNoteNameFromMIDI midiNote
            selectObject: dataTable
            Set string value: segment, "F" + string$(formantNum) + "_note", getNoteNameFromMIDI.noteName$
            
            # Calculate note name for display
            octave = floor((noteNum - 12) / 12)
            pitchClass = (noteNum - 12) mod 12
            
            # Note names
            if pitchClass = 0
                noteName$ = "C"
            elsif pitchClass = 1
                noteName$ = "C#"
            elsif pitchClass = 2
                noteName$ = "D"
            elsif pitchClass = 3
                noteName$ = "D#"
            elsif pitchClass = 4
                noteName$ = "E"
            elsif pitchClass = 5
                noteName$ = "F"
            elsif pitchClass = 6
                noteName$ = "F#"
            elsif pitchClass = 7
                noteName$ = "G"
            elsif pitchClass = 8
                noteName$ = "G#"
            elsif pitchClass = 9
                noteName$ = "A"
            elsif pitchClass = 10
                noteName$ = "A#"
            elsif pitchClass = 11
                noteName$ = "B"
            endif
            
            appendInfoLine: "  F", formantNum, ": ", fixed$(freq, 1), " Hz → ", 
                ... fixed$(midiCent, 1), " cents (MIDI ", fixed$(midiNote, 2), 
                ... " ≈ ", noteName$, octave, " ", 
                ... if cents_deviation >= 0 then "+" else "" fi, cents_deviation, "¢)"
        else
            appendInfoLine: "  F", formantNum, ": -- Hz (not detected)"
            selectObject: dataTable
            Set numeric value: segment, "F" + string$(formantNum) + "_Hz", 0
            Set numeric value: segment, "F" + string$(formantNum) + "_MIDI", 0
            Set numeric value: segment, "F" + string$(formantNum) + "_cents", 0
            Set string value: segment, "F" + string$(formantNum) + "_note", "--"
        endif
    endfor
    
    appendInfoLine: ""
endfor

appendInfoLine: "=== Analysis Complete ==="
appendInfoLine: ""

# ============================================================
# VISUALIZATION 1: Formant Trajectories Over Time
# ============================================================
if show_formant_trajectories
    appendInfoLine: "Creating Formant Trajectory Visualization..."
    
    # Create a new Picture window
    Erase all
    Select inner viewport: 0.5, 6.5, 0.5, 3
    
    # Find min and max formant values for scaling
    selectObject: dataTable
    minFreq = 10000
    maxFreq = 0
    for seg from 1 to number_of_segments
        for fnum from 1 to 4
            freq = Get value: seg, "F" + string$(fnum) + "_Hz"
            if freq > 0
                if freq < minFreq
                    minFreq = freq
                endif
                if freq > maxFreq
                    maxFreq = freq
                endif
            endif
        endfor
    endfor
    
    # Add some padding
    freqRange = maxFreq - minFreq
    minFreq = max(0, minFreq - freqRange * 0.1)
    maxFreq = maxFreq + freqRange * 0.1
    
    # Draw axes
    Axes: 0, duration, minFreq, maxFreq
    Draw inner box
    Text top: "yes", "Formant Trajectories Over Time"
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Frequency (Hz)"
    Marks bottom every: 1, duration / 10, "yes", "yes", "no"
    Marks left every: 1, (maxFreq - minFreq) / 5, "yes", "yes", "no"
    
    # Define colors for each formant
    f1Color$ = "Red"
    f2Color$ = "Blue"
    f3Color$ = "Green"
    f4Color$ = "Magenta"
    
    # Draw formant trajectories
    for fnum from 1 to 4
        if fnum = 1
            Colour: f1Color$
        elsif fnum = 2
            Colour: f2Color$
        elsif fnum = 3
            Colour: f3Color$
        elsif fnum = 4
            Colour: f4Color$
        endif
        
        # Draw line connecting points
        for seg from 1 to number_of_segments - 1
            selectObject: dataTable
            time1 = Get value: seg, "time"
            freq1 = Get value: seg, "F" + string$(fnum) + "_Hz"
            time2 = Get value: seg + 1, "time"
            freq2 = Get value: seg + 1, "F" + string$(fnum) + "_Hz"
            
            if freq1 > 0 and freq2 > 0
                Draw line: time1, freq1, time2, freq2
            endif
        endfor
        
        # Draw points
        Line width: 3
        for seg from 1 to number_of_segments
            selectObject: dataTable
            time = Get value: seg, "time"
            freq = Get value: seg, "F" + string$(fnum) + "_Hz"
            
            if freq > 0
                Paint circle: f1Color$, time, freq, 0.03
            endif
        endfor
        Line width: 1
    endfor
    
    # Add legend - moved to the right
    Select inner viewport: 6.8, 7.5, 0.5, 2
    Axes: 0, 1, 0, 1
    Colour: f1Color$
    Paint circle: f1Color$, 0.1, 0.9, 0.05
    Colour: "Black"
    Text: 0.3, "left", 0.9, "half", "F1"
    
    Colour: f2Color$
    Paint circle: f2Color$, 0.1, 0.7, 0.05
    Colour: "Black"
    Text: 0.3, "left", 0.7, "half", "F2"
    
    Colour: f3Color$
    Paint circle: f3Color$, 0.1, 0.5, 0.05
    Colour: "Black"
    Text: 0.3, "left", 0.5, "half", "F3"
    
    Colour: f4Color$
    Paint circle: f4Color$, 0.1, 0.3, 0.05
    Colour: "Black"
    Text: 0.3, "left", 0.3, "half", "F4"
    
    appendInfoLine: "✓ Formant Trajectory plot created"
endif

# ============================================================
# VISUALIZATION 2: MIDI Piano Roll
# ============================================================
if show_MIDI_piano_roll
    appendInfoLine: "Creating MIDI Piano Roll Visualization..."
    
    Erase all
    Select inner viewport: 0.5, 7.5, 0.5, 4
    
    # Find MIDI range
    selectObject: dataTable
    minMIDI = 200
    maxMIDI = 0
    for seg from 1 to number_of_segments
        for fnum from 1 to 4
            midiNote = Get value: seg, "F" + string$(fnum) + "_MIDI"
            if midiNote > 0
                if midiNote < minMIDI
                    minMIDI = midiNote
                endif
                if midiNote > maxMIDI
                    maxMIDI = midiNote
                endif
            endif
        endfor
    endfor
    
    # Round to nearest octave for better display
    minMIDI = floor(minMIDI / 12) * 12
    maxMIDI = ceiling(maxMIDI / 12) * 12
    
    # Draw axes
    Axes: 0.5, number_of_segments + 0.5, minMIDI, maxMIDI
    Draw inner box
    Text top: "yes", "MIDI Piano Roll - Formant Chords"
    Text bottom: "yes", "Segment Number"
    Text left: "yes", "MIDI Note Number"
    Marks bottom every: 1, 1, "yes", "yes", "no"
    
    # Draw note grid lines (every octave)
    Line width: 0.5
    Colour: "Silver"
    for note from minMIDI to maxMIDI
        if (note - 12) mod 12 = 0
            Draw line: 0.5, note, number_of_segments + 0.5, note
        endif
    endfor
    Line width: 1
    
    # Draw note rectangles for each formant in each segment
    boxWidth = 0.8 / 4
    for seg from 1 to number_of_segments
        for fnum from 1 to 4
            selectObject: dataTable
            midiNote = Get value: seg, "F" + string$(fnum) + "_MIDI"
            
            if midiNote > 0
                # Set color based on formant
                if fnum = 1
                    Colour: "Red"
                elsif fnum = 2
                    Colour: "Blue"
                elsif fnum = 3
                    Colour: "Green"
                elsif fnum = 4
                    Colour: "Magenta"
                endif
                
                # Draw rectangle for note
                xLeft = seg - 0.4 + (fnum - 1) * boxWidth
                xRight = xLeft + boxWidth
                yBottom = midiNote - 0.5
                yTop = midiNote + 0.5
                
                Paint rectangle: "Silver", xLeft, xRight, yBottom, yTop
                Colour: "Black"
                Draw rectangle: xLeft, xRight, yBottom, yTop
            endif
        endfor
    endfor
    
    # Add note name labels on left axis
    Colour: "Black"
    for note from minMIDI to maxMIDI
        if (note - 12) mod 12 = 0
            call getNoteNameFromMIDI note
            Text: 0.3, "right", note, "half", getNoteNameFromMIDI.noteName$
        endif
    endfor
    
    appendInfoLine: "✓ MIDI Piano Roll created"
endif

# ============================================================
# VISUALIZATION 3: Spectral Analysis (Formant Positions)
# ============================================================
if show_spectral_analysis
    appendInfoLine: "Creating Spectral Analysis Visualization..."
    
    Erase all
    
    # Calculate number of rows and columns for subplots
    numCols = ceiling(sqrt(number_of_segments))
    numRows = ceiling(number_of_segments / numCols)
    
    plotWidth = 7 / numCols
    plotHeight = 4.5 / numRows
    
    for seg from 1 to number_of_segments
        # Calculate subplot position - moved down by starting at 1.0 instead of 0.5
        row = floor((seg - 1) / numCols)
        col = (seg - 1) mod numCols
        
        xLeft = 0.5 + col * plotWidth
        xRight = xLeft + plotWidth - 0.2
        yBottom = 4.5 - (row + 1) * plotHeight + 0.5
        yTop = yBottom + plotHeight - 0.5
        
        Select inner viewport: xLeft, xRight, yBottom, yTop
        
        # Get formant frequencies for this segment
        selectObject: dataTable
        f1 = Get value: seg, "F1_Hz"
        f2 = Get value: seg, "F2_Hz"
        f3 = Get value: seg, "F3_Hz"
        f4 = Get value: seg, "F4_Hz"
        
        # Draw simple spectral representation
        Axes: 0, max_formant_Hz, 0, 1
        
        # Draw formant peaks
        if f1 > 0
            Colour: "Red"
            Draw line: f1, 0, f1, 0.9
        endif
        if f2 > 0
            Colour: "Blue"
            Draw line: f2, 0, f2, 0.75
        endif
        if f3 > 0
            Colour: "Green"
            Draw line: f3, 0, f3, 0.6
        endif
        if f4 > 0
            Colour: "Magenta"
            Draw line: f4, 0, f4, 0.45
        endif
        
        # Draw axes and labels
        Colour: "Black"
        Draw inner box
        Text top: "no", "Seg " + string$(seg)
    endfor
    
    appendInfoLine: "✓ Spectral Analysis created"
endif

# ============================================================
# VISUALIZATION 4: Chord Progression Summary
# ============================================================
if show_chord_progression
    appendInfoLine: "Creating Chord Progression Visualization..."
    
    Erase all
    Select inner viewport: 0.5, 7.5, 0.5, 5
    
    Axes: 0, 10, 0, number_of_segments + 1
    
    Text top: "yes", "Chord Progression Summary"
    
    # Draw table header
    Colour: "Black"
    Line width: 2
    Draw line: 0, number_of_segments + 0.5, 10, number_of_segments + 0.5
    Line width: 1
    
    Text: 1, "centre", number_of_segments + 0.75, "half", "Segment"
    Text: 3, "centre", number_of_segments + 0.75, "half", "Time (s)"
    Text: 5, "centre", number_of_segments + 0.75, "half", "F1 (Note)"
    Text: 6.5, "centre", number_of_segments + 0.75, "half", "F2 (Note)"
    Text: 8, "centre", number_of_segments + 0.75, "half", "F3 (Note)"
    Text: 9.5, "centre", number_of_segments + 0.75, "half", "F4 (Note)"
    
    # Draw rows for each segment
    for seg from 1 to number_of_segments
        yPos = number_of_segments - seg + 0.5
        
        selectObject: dataTable
        segNum = Get value: seg, "segment"
        time = Get value: seg, "time"
        f1Note$ = Get value: seg, "F1_note"
        f2Note$ = Get value: seg, "F2_note"
        f3Note$ = Get value: seg, "F3_note"
        f4Note$ = Get value: seg, "F4_note"
        
        # Alternate row shading
        if seg mod 2 = 0
            Colour: "{0.95, 0.95, 0.95}"
            Paint rectangle: "{0.95, 0.95, 0.95}", 0, 10, yPos - 0.4, yPos + 0.4
        endif
        
        Colour: "Black"
        Text: 1, "centre", yPos, "half", string$(segNum)
        Text: 3, "centre", yPos, "half", fixed$(time, 2)
        
        # Color-code formant notes
        Colour: "Red"
        Text: 5, "centre", yPos, "half", f1Note$
        Colour: "Blue"
        Text: 6.5, "centre", yPos, "half", f2Note$
        Colour: "Green"
        Text: 8, "centre", yPos, "half", f3Note$
        Colour: "Magenta"
        Text: 9.5, "centre", yPos, "half", f4Note$
    endfor
    
    # Draw grid lines
    Colour: "Silver"
    for seg from 0 to number_of_segments
        Draw line: 0, seg + 0.5, 10, seg + 0.5
    endfor
    
    appendInfoLine: "✓ Chord Progression Summary created"
endif

# ============================================================
# VISUALIZATION 5: Cent Deviations
# ============================================================
if show_cent_deviations
    appendInfoLine: "Creating Cent Deviation Visualization..."
    
    Erase all
    Select inner viewport: 0.5, 6.5, 0.5, 4
    
    # Draw axes (-50 to +50 cents)
    Axes: 0.5, number_of_segments + 0.5, -50, 50
    Draw inner box
    Text top: "yes", "Cent Deviations from Nearest MIDI Note"
    Text bottom: "yes", "Segment Number"
    Text left: "yes", "Cents (¢)"
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Marks left every: 1, 10, "yes", "yes", "yes"
    
    # Draw zero line (perfect tuning)
    Colour: "{0.7, 0.7, 0.7}"
    Line width: 2
    Draw line: 0.5, 0, number_of_segments + 0.5, 0
    Line width: 1
    
    # Draw quarter-tone reference lines
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0.5, -25, number_of_segments + 0.5, -25
    Draw line: 0.5, 25, number_of_segments + 0.5, 25
    
    # Define colors for each formant
    f1Color$ = "Red"
    f2Color$ = "Blue"
    f3Color$ = "Green"
    f4Color$ = "Magenta"
    
    # Draw cent deviation bars
    barWidth = 0.15
    for seg from 1 to number_of_segments
        selectObject: dataTable
        
        for fnum from 1 to 4
            cents = Get value: seg, "F" + string$(fnum) + "_cents"
            freq = Get value: seg, "F" + string$(fnum) + "_Hz"
            
            if freq > 0
                # Set color based on formant
                if fnum = 1
                    Colour: f1Color$
                elsif fnum = 2
                    Colour: f2Color$
                elsif fnum = 3
                    Colour: f3Color$
                elsif fnum = 4
                    Colour: f4Color$
                endif
                
                # Draw bar
                xLeft = seg - 0.3 + (fnum - 1) * barWidth
                xRight = xLeft + barWidth
                
                if cents >= 0
                    Paint rectangle: f1Color$, xLeft, xRight, 0, cents
                else
                    Paint rectangle: f1Color$, xLeft, xRight, cents, 0
                endif
                
                # Draw outline
                Colour: "Black"
                Line width: 0.5
                if cents >= 0
                    Draw rectangle: xLeft, xRight, 0, cents
                else
                    Draw rectangle: xLeft, xRight, cents, 0
                endif
                Line width: 1
            endif
        endfor
    endfor
    
    # Add legend - moved to the right
    Select inner viewport: 6.8, 7.5, 0.5, 2
    Axes: 0, 1, 0, 1
    
    Colour: f1Color$
    Paint rectangle: f1Color$, 0.05, 0.2, 0.85, 0.95
    Colour: "Black"
    Draw rectangle: 0.05, 0.2, 0.85, 0.95
    Text: 0.3, "left", 0.9, "half", "F1"
    
    Colour: f2Color$
    Paint rectangle: f2Color$, 0.05, 0.2, 0.65, 0.75
    Colour: "Black"
    Draw rectangle: 0.05, 0.2, 0.65, 0.75
    Text: 0.3, "left", 0.7, "half", "F2"
    
    Colour: f3Color$
    Paint rectangle: f3Color$, 0.05, 0.2, 0.45, 0.55
    Colour: "Black"
    Draw rectangle: 0.05, 0.2, 0.45, 0.55
    Text: 0.3, "left", 0.5, "half", "F3"
    
    Colour: f4Color$
    Paint rectangle: f4Color$, 0.05, 0.2, 0.25, 0.35
    Colour: "Black"
    Draw rectangle: 0.05, 0.2, 0.25, 0.35
    Text: 0.3, "left", 0.3, "half", "F4"
    
    appendInfoLine: "✓ Cent Deviation plot created"
endif

# Clean up
removeObject: formant
removeObject: dataTable

appendInfoLine: ""
appendInfoLine: "=== All Visualizations Complete ==="
appendInfoLine: "Check the Picture window for graphical displays"