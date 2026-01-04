# ============================================================
# Praat AudioTools - Chord_Generator_from_Audio.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Chord Generator from Audio - creates musical chords by
#   pitch-shifting copies of the input audio. Supports triads
#   and 7th chords with optional stereo spread.
#
# Changelog v0.2:
#   - Fixed mixing (was putting notes in separate channels!)
#   - Added stereo spread option
#   - Added visualization
#   - Added presets
# ============================================================

form Chord Generator from Audio
    comment Select a Sound object first
    
    comment === Chord Type ===
    optionmenu Chord_type 1
        option Major
        option Minor
        option Sus2
        option Sus4
        option Diminished
        option Augmented
        option Major 7th
        option Minor 7th
        option Dominant 7th
        option Power (5th)
    
    comment === Levels (0-1) ===
    real Root_level 0.8
    real Third_level 0.6
    real Fifth_level 0.5
    real Seventh_level 0.4
    
    comment === Stereo Spread ===
    boolean Create_stereo 1
    real Stereo_spread 0.6
    comment (0 = mono, 1 = hard L/R)
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
channels = Get number of channels
fs = Get sampling frequency
duration = Get total duration

# === Convert to Mono ===
if channels > 1
    selectObject: original
    monoSound = Convert to mono
else
    selectObject: original
    monoSound = Copy: "mono_source"
endif

# === Define Chord Intervals ===
# interval2 = 2nd note, interval3 = 3rd note, interval4 = 4th note (7ths)
has_seventh = 0

if chord_type = 1
    # Major
    interval2 = 4
    interval3 = 7
    chordName$ = "Major"
elsif chord_type = 2
    # Minor
    interval2 = 3
    interval3 = 7
    chordName$ = "Minor"
elsif chord_type = 3
    # Sus2
    interval2 = 2
    interval3 = 7
    chordName$ = "Sus2"
elsif chord_type = 4
    # Sus4
    interval2 = 5
    interval3 = 7
    chordName$ = "Sus4"
elsif chord_type = 5
    # Diminished
    interval2 = 3
    interval3 = 6
    chordName$ = "Dim"
elsif chord_type = 6
    # Augmented
    interval2 = 4
    interval3 = 8
    chordName$ = "Aug"
elsif chord_type = 7
    # Major 7th
    interval2 = 4
    interval3 = 7
    interval4 = 11
    has_seventh = 1
    chordName$ = "Maj7"
elsif chord_type = 8
    # Minor 7th
    interval2 = 3
    interval3 = 7
    interval4 = 10
    has_seventh = 1
    chordName$ = "Min7"
elsif chord_type = 9
    # Dominant 7th
    interval2 = 4
    interval3 = 7
    interval4 = 10
    has_seventh = 1
    chordName$ = "Dom7"
else
    # Power chord (5th)
    interval2 = 7
    interval3 = 12
    chordName$ = "Power"
endif

# === Info ===
writeInfoLine: "=== Chord Generator ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Chord: ", chordName$
appendInfoLine: ""

if has_seventh
    appendInfoLine: "Notes: Root, +", interval2, "st, +", interval3, "st, +", interval4, "st"
else
    appendInfoLine: "Notes: Root, +", interval2, "st, +", interval3, "st"
endif
appendInfoLine: ""

semitone_ratio = 2 ^ (1/12)

# === Create Root Note ===
selectObject: monoSound
rootNote = Copy: "root"
Scale peak: root_level

# === Pitch Shift Procedure ===
procedure pitchShift: .sourceID, .semitones, .outName$
    selectObject: .sourceID
    .tmpCopy = Copy: "tmp_shift"
    
    .ratio = semitone_ratio ^ .semitones
    .newFS = fs * .ratio
    
    Override sampling frequency: .newFS
    .manip = To Manipulation: 0.01, 75, 600
    .durTier = Extract duration tier
    
    selectObject: .durTier
    Add point: 0, .ratio
    
    selectObject: .manip, .durTier
    Replace duration tier
    
    selectObject: .manip
    .resyn = Get resynthesis (overlap-add)
    
    selectObject: .resyn
    .final = Resample: fs, 50
    Rename: .outName$
    
    removeObject: .durTier, .manip, .tmpCopy, .resyn
    
    .result = .final
endproc

# === Create Pitch-Shifted Notes ===
appendInfoLine: "Creating note 2 (+", interval2, " semitones)..."
@pitchShift: monoSound, interval2, "note2"
note2 = pitchShift.result
selectObject: note2
Scale peak: third_level

appendInfoLine: "Creating note 3 (+", interval3, " semitones)..."
@pitchShift: monoSound, interval3, "note3"
note3 = pitchShift.result
selectObject: note3
Scale peak: fifth_level

if has_seventh
    appendInfoLine: "Creating note 4 (+", interval4, " semitones)..."
    @pitchShift: monoSound, interval4, "note4"
    note4 = pitchShift.result
    selectObject: note4
    Scale peak: seventh_level
endif

# === Mix Notes Together ===
appendInfoLine: ""
appendInfoLine: "Mixing notes..."

if create_stereo
    # Create stereo with spread
    # Root: center
    # Note2: slightly left
    # Note3: slightly right
    # Note4: center (if exists)
    
    # Calculate pan positions
    rootPan = 0.5
    note2Pan = 0.5 - stereo_spread * 0.4
    note3Pan = 0.5 + stereo_spread * 0.4
    note4Pan = 0.5
    
    # Create L and R channels
    selectObject: monoSound
    Create Sound from formula: "mix_L", 1, 0, duration, fs, "0"
    mixL = selected("Sound")
    
    Create Sound from formula: "mix_R", 1, 0, duration, fs, "0"
    mixR = selected("Sound")
    
    # Add root (center)
    selectObject: mixL
    Formula: ~ self + Sound_root[] * sqrt(1 - rootPan)
    selectObject: mixR
    Formula: ~ self + Sound_root[] * sqrt(rootPan)
    
    # Add note2 (pan left)
    selectObject: mixL
    Formula: ~ self + Sound_note2[] * sqrt(1 - note2Pan)
    selectObject: mixR
    Formula: ~ self + Sound_note2[] * sqrt(note2Pan)
    
    # Add note3 (pan right)
    selectObject: mixL
    Formula: ~ self + Sound_note3[] * sqrt(1 - note3Pan)
    selectObject: mixR
    Formula: ~ self + Sound_note3[] * sqrt(note3Pan)
    
    # Add note4 if exists (center)
    if has_seventh
        selectObject: mixL
        Formula: ~ self + Sound_note4[] * sqrt(1 - note4Pan)
        selectObject: mixR
        Formula: ~ self + Sound_note4[] * sqrt(note4Pan)
    endif
    
    # Combine to stereo
    selectObject: mixL, mixR
    Combine to stereo
    result = selected("Sound")
    Rename: originalName$ + "_" + chordName$
    
    removeObject: mixL, mixR
else
    # Mono mix
    selectObject: rootNote
    Copy: "mix_mono"
    result = selected("Sound")
    
    Formula: ~ self + Sound_note2[] + Sound_note3[]
    
    if has_seventh
        Formula: ~ self + Sound_note4[]
    endif
    
    Rename: originalName$ + "_" + chordName$
endif

# Scale peak
selectObject: result
Scale peak: 0.95

# === Cleanup ===
removeObject: monoSound, rootNote, note2, note3
if has_seventh
    removeObject: note4
endif

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Chord Generator: " + originalName$ + " → " + chordName$
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.8
    Select inner viewport: 0.6, 7.6, 0.7, 1.7
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.9, 3.1
    Select inner viewport: 0.6, 7.6, 2.0, 3.0
    selectObject: result
    Colour: "{0.5, 0.6, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Chord"
    Text bottom: "yes", "Time (s)"
    
    # Chord diagram
    Select outer viewport: 0, 8, 3.3, 4.8
    Select inner viewport: 0.6, 7.6, 3.5, 4.7
    
    if has_seventh
        numNotes = 4
    else
        numNotes = 3
    endif
    
    Axes: 0, numNotes + 1, 0, 15
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, numNotes + 1, 0, 15
    
    # Draw note bars
    # Root
    Paint rectangle: "{0.5, 0.7, 0.5}", 0.6, 1.4, 0, 0.5
    Colour: "Black"
    Font size: 7
    Text: 1, "centre", 1, "half", "Root"
    Text: 1, "centre", -0.8, "half", "0 st"
    
    # Note 2
    Paint rectangle: "{0.5, 0.6, 0.8}", 1.6, 2.4, 0, interval2 + 0.5
    Text: 2, "centre", interval2 + 1.5, "half", "3rd"
    Text: 2, "centre", -0.8, "half", "+" + string$(interval2) + " st"
    
    # Note 3
    Paint rectangle: "{0.7, 0.5, 0.6}", 2.6, 3.4, 0, interval3 + 0.5
    Text: 3, "centre", interval3 + 1.5, "half", "5th"
    Text: 3, "centre", -0.8, "half", "+" + string$(interval3) + " st"
    
    # Note 4 (if 7th chord)
    if has_seventh
        Paint rectangle: "{0.8, 0.6, 0.5}", 3.6, 4.4, 0, interval4 + 0.5
        Text: 4, "centre", interval4 + 1.5, "half", "7th"
        Text: 4, "centre", -0.8, "half", "+" + string$(interval4) + " st"
    endif
    
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Semitones"
    
    # Stereo spread visualization
    if create_stereo
        Select outer viewport: 0, 8, 5.0, 5.4
        Select inner viewport: 0.6, 7.6, 5.05, 5.35
        
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.9, 0.9, 0.95}", 0, 1, 0, 1
        
        # Pan positions
        Colour: "{0.5, 0.7, 0.5}"
        Paint circle (mm): "{0.5, 0.7, 0.5}", rootPan, 0.5, 2
        
        Colour: "{0.5, 0.6, 0.8}"
        Paint circle (mm): "{0.5, 0.6, 0.8}", note2Pan, 0.5, 2
        
        Colour: "{0.7, 0.5, 0.6}"
        Paint circle (mm): "{0.7, 0.5, 0.6}", note3Pan, 0.5, 2
        
        if has_seventh
            Colour: "{0.8, 0.6, 0.5}"
            Paint circle (mm): "{0.8, 0.6, 0.5}", note4Pan, 0.5, 2
        endif
        
        Colour: "Black"
        Draw inner box
        Font size: 6
        Text: 0, "left", -0.3, "half", "L"
        Text: 1, "right", -0.3, "half", "R"
        Text: 0.5, "centre", -0.3, "half", "C"
        Text left: "yes", "Pan"
    endif
    
    # Stats
    Select outer viewport: 0, 8, 5.5, 5.8
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    if create_stereo
        Text: 0.5, "centre", 0.5, "half", "Chord: " + chordName$ + " | Notes: " + string$(numNotes) + " | Stereo spread: " + fixed$(stereo_spread, 2)
    else
        Text: 0.5, "centre", 0.5, "half", "Chord: " + chordName$ + " | Notes: " + string$(numNotes) + " | Mono output"
    endif
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result