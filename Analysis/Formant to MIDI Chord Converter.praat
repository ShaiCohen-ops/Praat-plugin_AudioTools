# ============================================================
# Praat AudioTools - Formant to MIDI Chord Converter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Formant to MIDI Chord Converter
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================
# Formant to MIDI Chord Converter
# This script segments selected audio, extracts 4 formants from each segment,
# converts them to MIDI cents, and displays the chords in the Info window

# Check if a Sound object is selected
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

# Get the selected Sound
sound = selected("Sound")
soundName$ = selected$("Sound")

# Parameters
form Formant Analysis Parameters
    positive Number_of_segments 8
    positive Time_step 0.01
    positive Max_formant_Hz 5500
    positive Number_of_formants 5
    positive Window_length 0.025
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

# Function to convert frequency (Hz) to MIDI cent
procedure freqToMidiCent: freq
    if freq > 0
        # MIDI note number = 69 + 12 * log2(freq/440)
        # MIDI cent = MIDI note * 100
        midiNote = 69 + 12 * ln(freq/440) / ln(2)
        .midiCent = midiNote * 100
    else
        .midiCent = 0
    endif
endproc

# Analyze each segment
for segment from 1 to number_of_segments
    # Calculate time point at center of segment
    startTime = (segment - 1) * segmentDuration
    endTime = segment * segmentDuration
    midTime = (startTime + endTime) / 2
    
    appendInfoLine: "--- Segment ", segment, " ---"
    appendInfoLine: "Time range: ", fixed$(startTime, 3), " - ", fixed$(endTime, 3), " s"
    appendInfoLine: "Analysis point: ", fixed$(midTime, 3), " s"
    
    # Extract formants at midpoint
    selectObject: formant
    
    appendInfoLine: "Chord (4-part harmony):"
    
    # Get formants F1-F4 and convert to MIDI cents
    for formantNum from 1 to 4
        freq = Get value at time: formantNum, midTime, "hertz", "Linear"
        
        if freq <> undefined and freq > 0
            call freqToMidiCent freq
            midiCent = freqToMidiCent.midiCent
            midiNote = midiCent / 100
            
            # Calculate note name
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
            
            cents_deviation = round((midiCent - noteNum * 100))
            
            appendInfoLine: "  F", formantNum, ": ", fixed$(freq, 1), " Hz → ", 
                ... fixed$(midiCent, 1), " cents (MIDI ", fixed$(midiNote, 2), 
                ... " ≈ ", noteName$, octave, " ", 
                ... if cents_deviation >= 0 then "+" else "" fi, cents_deviation, "¢)"
        else
            appendInfoLine: "  F", formantNum, ": -- Hz (not detected)"
        endif
    endfor
    
    appendInfoLine: ""
endfor

# Clean up
removeObject: formant

appendInfoLine: "=== Analysis Complete ==="