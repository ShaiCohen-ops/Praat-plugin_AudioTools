# ============================================================
# Praat AudioTools - Chord_Generator_from_Audio.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Chord Generator from Audio - creates musical chords by
#   pitch-shifting copies of the input audio. Supports triads
#   and 7th chords with optional stereo spread.
#
# Changelog v0.4.1: compact Summary typography/spacing; collision-safe gap after bottom-axis labels; DSP/analysis unchanged.
# Changelog v0.4: visualization standardization only - unified typography, summary/full-page Picture framing; DSP/analysis unchanged.
# Changelog v0.4:
#   - Keeps the existing design choice: multichannel input is folded to mono,
#     then Create_stereo optionally builds a new stereo chord image.
#   - Preserves the Sound time domain (xmin/xmax) through pitch shifting,
#     DurationTier use, and output mixing; non-zero start times now work.
#   - Replaces fixed 75-600 Hz Manipulation limits with adaptive analysis
#     limits derived from source pitch and requested transposition.
#   - Root/Third/Fifth/Seventh levels now act as linear gains rather than
#     per-voice peak normalization targets.
#   - Final output uses attenuation-only peak safety instead of always
#     normalizing to 0.95.
#   - Stereo_spread is clamped to 0..1 and now maps 1.0 to true hard L/R
#     placement for the two outer chord voices.
#   - Chord diagram labels are chord-aware (2nd/3rd/4th/5th/octave/etc.).
#   - Adds parameter validation and explicit axes for title/stats panels.
# Changelog v0.2:
#   - Fixed mixing (was putting notes in separate channels!)
#   - Added stereo spread option
#   - Added visualization
#   - Added presets
# ============================================================

form Chord Generator from Audio v0.4.1
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
xmin = Get start time
xmax = Get end time
duration = xmax - xmin

# === Validate Parameters ===
root_level = max(0, min(1, root_level))
third_level = max(0, min(1, third_level))
fifth_level = max(0, min(1, fifth_level))
seventh_level = max(0, min(1, seventh_level))
stereo_spread = max(0, min(1, stereo_spread))

# === Convert to Mono ===
if channels > 1
    selectObject: original
    monoSound = Convert to mono
else
    selectObject: original
    monoSound = Copy: "mono_source"
endif

# === Adaptive Pitch Analysis Bounds ===
# Analyse once on the mono source. The pitch-shift helper will expand the
# ceiling according to the requested transposition.
selectObject: monoSound
sourcePitch = To Pitch: 0.0, 40, 1200
median_f0 = Get quantile: 0, 0, 0.5, "Hertz"
removeObject: sourcePitch

if median_f0 = undefined
    analysis_floor = 40
    analysis_ceiling_base = 1200
    appendInfoLine: "Pitch analysis: no stable median detected; using broad bounds."
else
    analysis_floor = max(40, median_f0 / 4)
    analysis_ceiling_base = max(600, median_f0 * 4)
endif

# === Define Chord Intervals ===
# interval2 = 2nd note, interval3 = 3rd note, interval4 = 4th note (7ths)
has_seventh = 0

if chord_type = 1
    # Major
    interval2 = 4
    interval3 = 7
    chordName$ = "Major"
    note2Label$ = "Major 3rd"
    note3Label$ = "Perfect 5th"
elsif chord_type = 2
    # Minor
    interval2 = 3
    interval3 = 7
    chordName$ = "Minor"
    note2Label$ = "Minor 3rd"
    note3Label$ = "Perfect 5th"
elsif chord_type = 3
    # Sus2
    interval2 = 2
    interval3 = 7
    chordName$ = "Sus2"
    note2Label$ = "Major 2nd"
    note3Label$ = "Perfect 5th"
elsif chord_type = 4
    # Sus4
    interval2 = 5
    interval3 = 7
    chordName$ = "Sus4"
    note2Label$ = "Perfect 4th"
    note3Label$ = "Perfect 5th"
elsif chord_type = 5
    # Diminished
    interval2 = 3
    interval3 = 6
    chordName$ = "Dim"
    note2Label$ = "Minor 3rd"
    note3Label$ = "Diminished 5th"
elsif chord_type = 6
    # Augmented
    interval2 = 4
    interval3 = 8
    chordName$ = "Aug"
    note2Label$ = "Major 3rd"
    note3Label$ = "Augmented 5th"
elsif chord_type = 7
    # Major 7th
    interval2 = 4
    interval3 = 7
    interval4 = 11
    has_seventh = 1
    chordName$ = "Maj7"
    note2Label$ = "Major 3rd"
    note3Label$ = "Perfect 5th"
    note4Label$ = "Major 7th"
elsif chord_type = 8
    # Minor 7th
    interval2 = 3
    interval3 = 7
    interval4 = 10
    has_seventh = 1
    chordName$ = "Min7"
    note2Label$ = "Minor 3rd"
    note3Label$ = "Perfect 5th"
    note4Label$ = "Minor 7th"
elsif chord_type = 9
    # Dominant 7th
    interval2 = 4
    interval3 = 7
    interval4 = 10
    has_seventh = 1
    chordName$ = "Dom7"
    note2Label$ = "Major 3rd"
    note3Label$ = "Perfect 5th"
    note4Label$ = "Minor 7th"
else
    # Power chord (5th)
    interval2 = 7
    interval3 = 12
    chordName$ = "Power"
    note2Label$ = "Perfect 5th"
    note3Label$ = "Octave"
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
Formula: ~ self * root_level

# === Pitch Shift Procedure ===
procedure pitchShift: .sourceID, .semitones, .outName$
    selectObject: .sourceID
    .tmpCopy = Copy: "tmp_shift"

    .ratio = semitone_ratio ^ .semitones
    .newFS = fs * .ratio

    # Speaker-change style pitch shift: temporary sampling-rate override plus
    # inverse duration manipulation. Preserve xmin/xmax rather than assuming 0.
    Override sampling frequency: .newFS

    .ceil = analysis_ceiling_base * .ratio
    if .ceil < 600
        .ceil = 600
    endif
    if .ceil > .newFS * 0.45
        .ceil = .newFS * 0.45
    endif
    .floor = analysis_floor
    if .floor >= .ceil
        .floor = max(40, .ceil / 4)
    endif

    .manip = To Manipulation: 0.01, .floor, .ceil
    .durTier = Extract duration tier

    selectObject: .durTier
    Add point: xmin, .ratio
    Add point: xmax, .ratio

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
Formula: ~ self * third_level

appendInfoLine: "Creating note 3 (+", interval3, " semitones)..."
@pitchShift: monoSound, interval3, "note3"
note3 = pitchShift.result
selectObject: note3
Formula: ~ self * fifth_level

if has_seventh
    appendInfoLine: "Creating note 4 (+", interval4, " semitones)..."
    @pitchShift: monoSound, interval4, "note4"
    note4 = pitchShift.result
    selectObject: note4
    Formula: ~ self * seventh_level
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
    note2Pan = 0.5 - stereo_spread * 0.5
    note3Pan = 0.5 + stereo_spread * 0.5
    note4Pan = 0.5
    
    # Create L and R channels
    selectObject: monoSound
    Create Sound from formula: "mix_L", 1, xmin, xmax, fs, "0"
    mixL = selected("Sound")
    
    Create Sound from formula: "mix_R", 1, xmin, xmax, fs, "0"
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

# Attenuation-only peak safety
selectObject: result
finalPeak = Get absolute extremum: 0, 0, "None"
if finalPeak > 0.95
    Scale peak: 0.95
    safetyApplied = 1
else
    safetyApplied = 0
endif

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
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Chord Generator from Audio v0.4.1: " + originalName$ + " → " + chordName$
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.8
    Select inner viewport: 0.6, 7.6, 0.7, 1.7
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
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
    Text: 2, "centre", interval2 + 1.5, "half", note2Label$
    Text: 2, "centre", -0.8, "half", "+" + string$(interval2) + " st"
    
    # Note 3
    Paint rectangle: "{0.7, 0.5, 0.6}", 2.6, 3.4, 0, interval3 + 0.5
    Text: 3, "centre", interval3 + 1.5, "half", note3Label$
    Text: 3, "centre", -0.8, "half", "+" + string$(interval3) + " st"
    
    # Note 4 (if 7th chord)
    if has_seventh
        Paint rectangle: "{0.8, 0.6, 0.5}", 3.6, 4.4, 0, interval4 + 0.5
        Text: 4, "centre", interval4 + 1.5, "half", note4Label$
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
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    if create_stereo
        Text: 0.5, "centre", 0.5, "half", "Chord: " + chordName$ + " | Notes: " + string$(numNotes) + " | Stereo spread: " + fixed$(stereo_spread, 2)
    else
        Text: 0.5, "centre", 0.5, "half", "Chord: " + chordName$ + " | Notes: " + string$(numNotes) + " | Mono output"
    endif
    
    Font size: 10
    Colour: "Black"

    # ----------------------------------------------------------
    # Summary strip
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.92, 6.48
    Select inner viewport: 0.60, 7.70, 5.92 + 0.04, 6.48 - 0.04
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.72, "half", "##Summary##"
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.02, "left", 0.45, "half", "Detected source pitch • chord intervals • generated voices"
    Text: 0.02, "left", 0.20, "half", "Chord Generator from Audio • run parameters are reported in the Info window"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    pageHeight = 6.58
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Peak safety applied: ", safetyApplied

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result
