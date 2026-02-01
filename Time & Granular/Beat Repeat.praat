# ============================================================
# Praat AudioTools - Beat_Repeat.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Bug fixes
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Beat Repeat effect - extracts a rhythmically-aligned segment
#   and repeats it with optional amplitude decay. Classic DJ/
#   production tool for stutters, fills, and glitch effects.
#
# Changelog v0.2:
#   - Fixed fade out position
#   - Added visualization
#   - Added play option
#   - Added presets
# ============================================================

form Beat Repeat
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Stutter 1/16
        option Fast Stutter 1/32
        option Slow Repeat 1/4
        option Triplet Fill
        option Decaying Echo
        option Glitch Burst
    
    comment === Tempo ===
    real Bpm 120
    optionmenu Note_value 2
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
    
    comment === Beat Selection ===
    optionmenu Beat_selection_mode 1
        option Specific beat number
        option Random beat
        option Beat range
        option Auto (1 second in)
    integer Specific_beat 4
    integer Beat_range_start 2
    integer Beat_range_end 4
    
    comment === Repeat Parameters ===
    integer Num_repeats 4
    real Amplitude_decay 0.9
    
    comment === Options ===
    boolean Fade_repeats 0
    real Fade_duration_s 0.01
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Stutter 1/16
    note_value = 2
    num_repeats = 4
    amplitude_decay = 1.0
    fade_repeats = 0
elsif preset = 3
    # Fast Stutter 1/32
    note_value = 1
    num_repeats = 8
    amplitude_decay = 1.0
    fade_repeats = 0
elsif preset = 4
    # Slow Repeat 1/4
    note_value = 4
    num_repeats = 4
    amplitude_decay = 0.85
    fade_repeats = 1
    fade_duration_s = 0.02
elsif preset = 5
    # Triplet Fill
    note_value = 7
    num_repeats = 6
    amplitude_decay = 0.95
    fade_repeats = 0
elsif preset = 6
    # Decaying Echo
    note_value = 3
    num_repeats = 8
    amplitude_decay = 0.7
    fade_repeats = 1
    fade_duration_s = 0.01
elsif preset = 7
    # Glitch Burst
    note_value = 1
    num_repeats = 16
    amplitude_decay = 0.95
    fade_repeats = 0
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

sound = selected("Sound")
sound_name$ = selected$("Sound")

selectObject: sound
duration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels

# === Calculate Timing ===
secondsPerBeat = 60 / bpm
totalBeats = floor(duration / secondsPerBeat)

# Calculate note duration
if note_value = 1
    noteDuration = secondsPerBeat / 8  
    note_name$ = "1/32"
elsif note_value = 2
    noteDuration = secondsPerBeat / 4  
    note_name$ = "1/16"
elsif note_value = 3
    noteDuration = secondsPerBeat / 2  
    note_name$ = "1/8"
elsif note_value = 4
    noteDuration = secondsPerBeat      
    note_name$ = "1/4"
elsif note_value = 5
    noteDuration = secondsPerBeat * 2  
    note_name$ = "1/2"
elsif note_value = 6
    noteDuration = (secondsPerBeat / 4) * (2/3)
    note_name$ = "1/16 triplet"
elsif note_value = 7
    noteDuration = (secondsPerBeat / 2) * (2/3)
    note_name$ = "1/8 triplet"
elsif note_value = 8
    noteDuration = secondsPerBeat * (2/3)
    note_name$ = "1/4 triplet"
elsif note_value = 9
    noteDuration = secondsPerBeat / 4 * 1.5  
    note_name$ = "dotted 1/16"
elsif note_value = 10
    noteDuration = secondsPerBeat / 2 * 1.5  
    note_name$ = "dotted 1/8"
elsif note_value = 11
    noteDuration = secondsPerBeat * 1.5      
    note_name$ = "dotted 1/4"
elsif note_value = 12
    noteDuration = secondsPerBeat * 2 * 1.5  
    note_name$ = "dotted 1/2"
endif

# === Info ===
writeInfoLine: "=== Beat Repeat ==="
appendInfoLine: "Source: ", sound_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "BPM: ", bpm, " | Total beats: ", totalBeats
appendInfoLine: "Note value: ", note_name$, " (", fixed$(noteDuration * 1000, 1), " ms)"
appendInfoLine: ""

# === Determine Beat Selection ===
if beat_selection_mode = 1
    # Specific beat number
    selectedBeat = specific_beat
    if selectedBeat < 1
        selectedBeat = 1
    endif
    if selectedBeat > totalBeats
        selectedBeat = totalBeats
    endif
    appendInfoLine: "Mode: Specific beat #", selectedBeat
    
elsif beat_selection_mode = 2
    # Random beat (avoid first and last)
    if totalBeats > 2
        selectedBeat = randomInteger(2, totalBeats - 1)
    else
        selectedBeat = 1
    endif
    appendInfoLine: "Mode: Random beat #", selectedBeat
    
elsif beat_selection_mode = 3
    # Beat range
    rangeStart = beat_range_start
    rangeEnd = beat_range_end
    if rangeStart < 1
        rangeStart = 1
    endif
    if rangeEnd > totalBeats
        rangeEnd = totalBeats
    endif
    if rangeStart > rangeEnd
        temp = rangeStart
        rangeStart = rangeEnd
        rangeEnd = temp
    endif
    appendInfoLine: "Mode: Beat range #", rangeStart, " to #", rangeEnd
    selectedBeat = rangeStart
    
else
    # Auto mode (1 second in)
    startTime = 1.0
    if duration < 2.0
        startTime = duration * 0.25
    endif
    selectedBeat = floor(startTime / secondsPerBeat) + 1
    appendInfoLine: "Mode: Auto beat #", selectedBeat
endif

# === Calculate Start Time ===
if beat_selection_mode <> 4
    startTime = (selectedBeat - 1) * secondsPerBeat
endif

# Ensure we don't go past the end
if startTime + noteDuration > duration
    startTime = duration - noteDuration
    if startTime < 0
        startTime = 0
        noteDuration = duration
    endif
endif

appendInfoLine: "Extract from: ", fixed$(startTime, 3), " s"

# === Extract Segment ===
selectObject: sound
segment = Extract part: startTime, startTime + noteDuration, "Hanning", 1.0, "no"
Rename: "segment"

# Check level
selectObject: segment
segment_rms = Get root-mean-square: 0, 0
if segment_rms < 0.0001
    appendInfoLine: "WARNING: Segment is very quiet - consider different beat"
endif

# Apply fades if requested
if fade_repeats = 1
    selectObject: segment
    segDur = Get total duration
    fadeDur = min(fade_duration_s, segDur * 0.3)
    Fade in: 0, 0, fadeDur, "yes"
    Fade out: 0, segDur - fadeDur, fadeDur, "yes"
endif

# === Extract Before Part ===
selectObject: sound
if startTime > 0
    before = Extract part: 0, startTime, "rectangular", 1.0, "no"
    hasBefore = 1
else
    hasBefore = 0
endif

# === Create Repeats ===
appendInfoLine: "Creating ", num_repeats, " repeats (decay: ", amplitude_decay, ")..."

selectObject: segment
repeated = Copy: "repeated"

for i from 2 to num_repeats
    selectObject: segment
    this_repeat = Copy: "temp_repeat"
    
    # Apply amplitude decay
    decayFactor = amplitude_decay ^ (i - 1)
    Formula: "self * " + string$(decayFactor)
    
    # Concatenate
    selectObject: repeated, this_repeat
    new_repeated = Concatenate
    removeObject: repeated, this_repeat
    repeated = new_repeated
endfor

Rename: "repeated_section"

selectObject: repeated
repeatedDuration = Get total duration

# === Handle Beat Range Mode ===
if beat_selection_mode = 3
    rangeLength = (rangeEnd - rangeStart + 1) * secondsPerBeat
    afterStart = startTime + rangeLength
else
    afterStart = startTime + noteDuration
endif

# === Extract After Part ===
selectObject: sound
if afterStart < duration
    after = Extract part: afterStart, duration, "rectangular", 1.0, "no"
    hasAfter = 1
else
    hasAfter = 0
endif

# === Assemble Result ===
appendInfoLine: "Assembling result..."

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
    result = Copy: "result"
endif

Rename: sound_name$ + "_beatRepeat"

# Cleanup
removeObject: segment, repeated

# === Get Result Info ===
selectObject: result
resultDuration = Get total duration

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 1, 8, 0.2, 0.7
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Beat Repeat: " + sound_name$
    
    # Original waveform
    Select outer viewport: 0, 8, 0.9, 2.5
    Select inner viewport: 0.6, 7.6, 1.0, 2.4
    selectObject: sound
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    # Mark the extracted segment
    Colour: "{1, 0.3, 0.3}"
    Line width: 2
    Axes: 0, duration, -1, 1
    Draw line: startTime, -1, startTime, 1
    Draw line: startTime + noteDuration, -1, startTime + noteDuration, 1
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 2.6, 4.2
    Select inner viewport: 0.6, 7.6, 2.7, 4.1
    selectObject: result
    Colour: "{0.2, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    # Mark repeat section
    Colour: "{0.3, 0.8, 0.3}"
    Line width: 2
    Axes: 0, resultDuration, -1, 1
    Draw line: startTime, -1, startTime, 1
    Draw line: startTime + repeatedDuration, -1, startTime + repeatedDuration, 1
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Result"
    Text bottom: "yes", "Time (s)"
    
    # Legend
    Select outer viewport: 0, 8, 4.4, 4.8
    Font size: 8
    Colour: "{0.4, 0.4, 0.4}"
    Text: 2.5, "centre", 0.5, "half", "BPM: " + string$(bpm) + " | Note: " + note_name$ + " | Repeats: " + string$(num_repeats) + " | Decay: " + fixed$(amplitude_decay, 2)
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Original: ", fixed$(duration, 2), " s"
appendInfoLine: "Result: ", fixed$(resultDuration, 2), " s"
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result