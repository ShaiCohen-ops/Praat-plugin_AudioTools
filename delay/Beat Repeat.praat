form Beat Repeat Parameters
    real bpm 120
    optionmenu note_value 1
        option 1/32
        option 1/16
        option 1/8
        option 1/4
        option 1/2
        option 1/16 triplet
        option 1/8 triplet
        option 1/4 triplet
        option dotted 1/16
        option dotted 1/8
        option dotted 1/4
        option dotted 1/2
    integer num_repeats 4
    real amplitude_decay 0.9
endform

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

sound = selected("Sound")
sound_name$ = selected$("Sound")

selectObject: sound
duration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels

writeInfoLine: "=== Beat Repeat Processing ==="
appendInfoLine: "Original duration: ", fixed$(duration, 3), " seconds"

secondsPerBeat = 60 / bpm

# Calculate note duration based on selection
if note_value = 1
    noteDuration = secondsPerBeat / 8  
# 1/32 note
    note_name$ = "thirty-second"
elsif note_value = 2
    noteDuration = secondsPerBeat / 4  
# 1/16 note
    note_name$ = "sixteenth"
elsif note_value = 3
    noteDuration = secondsPerBeat / 2  
# 1/8 note
    note_name$ = "eighth"
elsif note_value = 4
    noteDuration = secondsPerBeat      
# 1/4 note
    note_name$ = "quarter"
elsif note_value = 5
    noteDuration = secondsPerBeat * 2  
# 1/2 note
    note_name$ = "half"
elsif note_value = 6
    noteDuration = (secondsPerBeat * 2) / 3  
# 1/16 triplet (two beats divided by 3)
    note_name$ = "sixteenth triplet"
elsif note_value = 7
    noteDuration = (secondsPerBeat * 4) / 3  
# 1/8 triplet (four beats divided by 3)
    note_name$ = "eighth triplet"
elsif note_value = 8
    noteDuration = (secondsPerBeat * 8) / 3  
# 1/4 triplet (eight beats divided by 3)
    note_name$ = "quarter triplet"
elsif note_value = 9
    noteDuration = secondsPerBeat / 4 * 1.5  
# dotted 1/16
    note_name$ = "dotted sixteenth"
elsif note_value = 10
    noteDuration = secondsPerBeat / 2 * 1.5  
# dotted 1/8
    note_name$ = "dotted eighth"
elsif note_value = 11
    noteDuration = secondsPerBeat * 1.5      
# dotted 1/4
    note_name$ = "dotted quarter"
elsif note_value = 12
    noteDuration = secondsPerBeat * 2 * 1.5  
# dotted 1/2
    note_name$ = "dotted half"
endif

appendInfoLine: "Note value: ", note_name$, " note (", fixed$(noteDuration, 3), " sec)"

# Find a good starting point (avoid very beginning)
startTime = 1.0
if duration < 2.0
    startTime = 0.1
endif

if startTime + noteDuration > duration
    startTime = duration - noteDuration
    if startTime < 0
        startTime = 0
        noteDuration = duration
    endif
endif

appendInfoLine: "Start time: ", fixed$(startTime, 3), " seconds"

# Extract the segment to repeat
selectObject: sound
segment = Extract part: startTime, startTime + noteDuration, "rectangular", 1.0, "no"
Rename: sound_name$ + "_segment"

# Check segment audio level
selectObject: segment
segment_rms = Get root-mean-square: 0, 0
appendInfoLine: "Segment RMS: ", fixed$(segment_rms, 6)

if segment_rms < 0.0001
    appendInfoLine: "WARNING: Segment is very quiet - trying a different position"
    nocheck removeObject: segment
    
    # Try a position at 25% of the file
    startTime = duration * 0.25
    if startTime + noteDuration > duration
        startTime = duration - noteDuration
    endif
    if startTime < 0
        startTime = 0
    endif
    
    segment = Extract part: startTime, startTime + noteDuration, "rectangular", 1.0, "no"
    selectObject: segment
    segment_rms = Get root-mean-square: 0, 0
    appendInfoLine: "New segment RMS: ", fixed$(segment_rms, 6)
endif

# Create before part
selectObject: sound
if startTime > 0
    before = Extract part: 0, startTime, "rectangular", 1.0, "no"
    hasBefore = 1
else
    hasBefore = 0
endif

# Create repeats with simple amplitude decay
appendInfoLine: "Creating ", num_repeats, " repeats..."

# Create the repeated section by concatenating copies
selectObject: segment
repeated = Copy: "temp_first_repeat"

for i from 2 to num_repeats
    selectObject: segment
    this_repeat = Copy: "temp_repeat_" + string$(i)
    
    # Apply amplitude decay
    decayFactor = amplitude_decay^(i-1)
    Formula: "self * " + string$(decayFactor)
    
    # Add to the repeated section
    selectObject: repeated, this_repeat
    new_repeated = Concatenate
    removeObject: repeated, this_repeat
    repeated = new_repeated
endfor

Rename: sound_name$ + "_repeated"

# Get repeated section duration
selectObject: repeated
repeatedDuration = Get total duration
afterStart = startTime + noteDuration  
# Use original segment duration, not repeated duration

appendInfoLine: "Repeated section duration: ", fixed$(repeatedDuration, 3), " seconds"

# Create after part
selectObject: sound
if afterStart < duration
    after = Extract part: afterStart, duration, "rectangular", 1.0, "no"
    hasAfter = 1
else
    hasAfter = 0
endif

# Create final result
appendInfoLine: "Creating final result..."

if hasBefore = 1 and hasAfter = 1
    selectObject: before, repeated, after
    result = Concatenate
    removeObject: before, after
elsif hasBefore = 1 and hasAfter = 0
    selectObject: before, repeated
    result = Concatenate
    removeObject: before
elsif hasBefore = 0 and hasAfter = 1
    selectObject: repeated, after
    result = Concatenate
    removeObject: after
else
    selectObject: repeated
    result = Copy: sound_name$ + "_beat_repeat"
endif

Rename: sound_name$ + "_beat_repeat"
Play

# Final cleanup
nocheck removeObject: segment
nocheck removeObject: repeated

selectObject: result
resultDuration = Get total duration
final_rms = Get root-mean-square: 0, 0

appendInfoLine: ""
appendInfoLine: "=== Result ==="
appendInfoLine: "Output duration: ", fixed$(resultDuration, 3), " seconds"
appendInfoLine: "Final RMS: ", fixed$(final_rms, 6)

if final_rms < 0.0001
    appendInfoLine: "WARNING: Output is very quiet!"
    appendInfoLine: "Try selecting a different part of the sound or increasing amplitude_decay"
else
    appendInfoLine: "Beat repeat effect complete!"
endif

appendInfoLine: ""
appendInfoLine: "The new sound '", sound_name$, "_beat_repeat' has been created."

# Select the result for immediate playback
selectObject: result