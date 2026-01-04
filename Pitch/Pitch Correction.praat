# ============================================================
# Praat AudioTools - Pitch_Correction.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Pitch Correction (Auto-Tune) - quantizes pitch to musical
#   scales. Supports major, minor, pentatonic, and modal scales.
#   Adjustable correction strength from natural to hard auto-tune.
#
# Changelog v0.2:
#   - Fixed comparison operators
#   - Modern syntax
#   - Added visualization with scale grid
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
name$ = selected$("Sound")

selectObject: original
duration = Get total duration
fs = Get sampling frequency

# === Form ===
form Pitch Correction
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Natural Correction
        option Hard Auto-Tune
        option Robot / Monotone
    
    comment === Musical Key ===
    optionmenu Root_Note 1
        option C
        option C# / Db
        option D
        option D# / Eb
        option E
        option F
        option F# / Gb
        option G
        option G# / Ab
        option A
        option A# / Bb
        option B
    
    optionmenu Scale_Type 2
        option Chromatic (All notes)
        option Major (Ionian)
        option Minor (Natural)
        option Minor (Harmonic)
        option Pentatonic Major
        option Pentatonic Minor
        option Dorian
        option Phrygian
        option Lydian
        option Mixolydian
    
    comment === Correction ===
    integer Transpose_semitones 0
    positive Strength_percent 100
    
    comment === Analysis ===
    positive Pitch_time_step 0.01
    positive Min_pitch 75
    positive Max_pitch 600
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
strength = strength_percent
smooth_amount = 0

if preset = 2
    # Natural
    strength = 60
    smooth_amount = 2.0
    presetName$ = "Natural"
elsif preset = 3
    # Hard Auto-Tune
    strength = 100
    smooth_amount = 0
    presetName$ = "Hard"
elsif preset = 4
    # Robot
    strength = 100
    smooth_amount = 10.0
    presetName$ = "Robot"
else
    presetName$ = "Custom"
endif

# === Get Scale/Root Names ===
rootNames$# = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
rootName$ = rootNames$#[root_Note]

scaleNames$# = {"Chromatic", "Major", "Minor", "Harm Min", "Pent Maj", "Pent Min", "Dorian", "Phrygian", "Lydian", "Mixolydian"}
scaleName$ = scaleNames$#[scale_Type]

# === Define Scale Patterns ===
# Patterns: semitones 0-11, "1"=allowed, "0"=skip
pat$ = "111111111111"

if scale_Type = 2
    # Major (W W H W W W H) -> 0 2 4 5 7 9 11
    pat$ = "101011010101"
elsif scale_Type = 3
    # Minor Natural -> 0 2 3 5 7 8 10
    pat$ = "101101011010"
elsif scale_Type = 4
    # Minor Harmonic -> 0 2 3 5 7 8 11
    pat$ = "101101011001"
elsif scale_Type = 5
    # Pentatonic Major -> 0 2 4 7 9
    pat$ = "101010010100"
elsif scale_Type = 6
    # Pentatonic Minor -> 0 3 5 7 10
    pat$ = "100101010010"
elsif scale_Type = 7
    # Dorian -> 0 2 3 5 7 9 10
    pat$ = "101101010110"
elsif scale_Type = 8
    # Phrygian -> 0 1 3 5 7 8 10
    pat$ = "110101011010"
elsif scale_Type = 9
    # Lydian -> 0 2 4 6 7 9 11
    pat$ = "101010110101"
elsif scale_Type = 10
    # Mixolydian -> 0 2 4 5 7 9 10
    pat$ = "101011010110"
endif

root_idx = root_Note - 1

# === Info ===
writeInfoLine: "=== Pitch Correction ==="
appendInfoLine: "Source: ", name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Key: ", rootName$, " ", scaleName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Strength: ", strength, "%"
if smooth_amount > 0
    appendInfoLine: "Smoothing: ", smooth_amount, " Hz"
endif
if transpose_semitones <> 0
    appendInfoLine: "Transpose: ", transpose_semitones, " st"
endif
appendInfoLine: ""

# === Create Manipulation ===
appendInfoLine: "Analyzing pitch..."
selectObject: original
manipulation = To Manipulation: pitch_time_step, min_pitch, max_pitch

selectObject: manipulation
pitchTier = Extract pitch tier

# === Smoothing (for Robot effect) ===
if smooth_amount > 0
    selectObject: pitchTier
    Stylize: smooth_amount, "Hz"
endif

# === Create Corrected Pitch Tier ===
selectObject: pitchTier
correctedTier = Copy: "Corrected"

selectObject: correctedTier
n = Get number of points

# Store for visualization
maxVizPoints = min(n, 500)
vizTimes# = zero#(maxVizPoints)
vizOrigPitch# = zero#(maxVizPoints)
vizCorrPitch# = zero#(maxVizPoints)
vizStep = ceiling(n / maxVizPoints)

appendInfoLine: "Correcting ", n, " pitch points..."

corrected_count = 0

for i from 1 to n
    selectObject: pitchTier
    origVal = Get value at index: i
    time = Get time from index: i
    
    if origVal > 50 and origVal < 1000
        # A. Convert Hz to MIDI
        midi_float = 69 + 12 * log2(origVal / 440)
        midi_round = round(midi_float)
        
        # B. Get pitch class relative to root (0-11)
        pc_raw = (midi_round - root_idx) mod 12
        if pc_raw < 0
            pc_raw = pc_raw + 12
        endif
        
        # C. Check scale pattern
        is_allowed$ = mid$(pat$, pc_raw + 1, 1)
        
        if is_allowed$ = "0"
            # Note out of scale - find nearest
            corrected_count = corrected_count + 1
            
            # Check upper (+1)
            pc_up = (pc_raw + 1) mod 12
            allowed_up$ = mid$(pat$, pc_up + 1, 1)
            
            # Check lower (-1)
            pc_down = pc_raw - 1
            if pc_down < 0
                pc_down = 11
            endif
            allowed_down$ = mid$(pat$, pc_down + 1, 1)
            
            # Snap to nearest allowed
            if allowed_up$ = "1" and allowed_down$ = "0"
                midi_round = midi_round + 1
            elsif allowed_down$ = "1" and allowed_up$ = "0"
                midi_round = midi_round - 1
            elsif allowed_down$ = "1" and allowed_up$ = "1"
                # Both valid - snap to closer
                diff = midi_float - midi_round
                if diff > 0
                    midi_round = midi_round + 1
                else
                    midi_round = midi_round - 1
                endif
            endif
        endif
        
        # D. Convert target MIDI back to Hz
        target_val = 440 * (2 ^ ((midi_round - 69) / 12))
        
        # E. Apply transpose
        if transpose_semitones <> 0
            target_val = target_val * (2 ^ (transpose_semitones / 12))
        endif
        
        # F. Blend with strength
        final_val = origVal + (target_val - origVal) * (strength / 100)
        
        # Store for visualization
        vizIdx = ceiling(i / vizStep)
        if vizIdx >= 1 and vizIdx <= maxVizPoints
            if vizTimes#[vizIdx] = 0
                vizTimes#[vizIdx] = time
                vizOrigPitch#[vizIdx] = origVal
                vizCorrPitch#[vizIdx] = final_val
            endif
        endif
        
        selectObject: correctedTier
        Remove point: i
        Add point: time, final_val
    endif
endfor

appendInfoLine: "Notes corrected: ", corrected_count

# === Resynthesize ===
appendInfoLine: ""
appendInfoLine: "Resynthesizing..."

selectObject: manipulation, correctedTier
Replace pitch tier

selectObject: manipulation
result = Get resynthesis (overlap-add)
Rename: name$ + "_" + rootName$ + scaleName$

selectObject: result
Scale peak: 0.95

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Pitch Correction: " + name$ + " → " + rootName$ + " " + scaleName$
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.6, 0.7, 1.4
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.6, 2.5
    Select inner viewport: 0.6, 7.6, 1.7, 2.4
    selectObject: result
    Colour: "{0.5, 0.7, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Corrected"
    Text bottom: "yes", "Time (s)"
    
    # Pitch correction visualization
    Select outer viewport: 0, 8, 2.7, 4.8
    Select inner viewport: 0.6, 7.6, 2.9, 4.7
    
    # Find pitch range
    minP = 1000
    maxP = 50
    for vp from 1 to maxVizPoints
        if vizOrigPitch#[vp] > 0
            if vizOrigPitch#[vp] < minP
                minP = vizOrigPitch#[vp]
            endif
            if vizOrigPitch#[vp] > maxP
                maxP = vizOrigPitch#[vp]
            endif
        endif
        if vizCorrPitch#[vp] > 0
            if vizCorrPitch#[vp] < minP
                minP = vizCorrPitch#[vp]
            endif
            if vizCorrPitch#[vp] > maxP
                maxP = vizCorrPitch#[vp]
            endif
        endif
    endfor
    
    # Expand to nearest MIDI notes
    minMidi = floor(69 + 12 * log2(minP / 440)) - 1
    maxMidi = ceiling(69 + 12 * log2(maxP / 440)) + 1
    
    minP = 440 * (2 ^ ((minMidi - 69) / 12))
    maxP = 440 * (2 ^ ((maxMidi - 69) / 12))
    
    Axes: 0, duration, minP, maxP
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, minP, maxP
    
    # Draw scale grid lines
    for midi from minMidi to maxMidi
        freq = 440 * (2 ^ ((midi - 69) / 12))
        pc = (midi - root_idx) mod 12
        if pc < 0
            pc = pc + 12
        endif
        
        inScale$ = mid$(pat$, pc + 1, 1)
        
        if inScale$ = "1"
            # Scale note - draw solid line
            Colour: "{0.7, 0.85, 0.7}"
            Line width: 1.5
        else
            # Non-scale note - draw faint line
            Colour: "{0.9, 0.9, 0.9}"
            Line width: 0.5
        endif
        
        Draw line: 0, freq, duration, freq
    endfor
    Line width: 1
    
    # Draw original pitch (gray)
    Colour: "{0.6, 0.6, 0.6}"
    for vp from 2 to maxVizPoints
        if vizOrigPitch#[vp] > 0 and vizOrigPitch#[vp - 1] > 0
            Draw line: vizTimes#[vp - 1], vizOrigPitch#[vp - 1], vizTimes#[vp], vizOrigPitch#[vp]
        endif
    endfor
    
    # Draw corrected pitch (blue)
    Colour: "{0.3, 0.5, 0.8}"
    Line width: 1.5
    for vp from 2 to maxVizPoints
        if vizCorrPitch#[vp] > 0 and vizCorrPitch#[vp - 1] > 0
            Draw line: vizTimes#[vp - 1], vizCorrPitch#[vp - 1], vizTimes#[vp], vizCorrPitch#[vp]
        endif
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Pitch (Hz)"
    Text bottom: "yes", "Time (s)"
    
    # Legend
    Font size: 6
    Colour: "{0.6, 0.6, 0.6}"
    Text: 0.85, "left", 1.05, "half", "Original"
    Colour: "{0.3, 0.5, 0.8}"
    Text: 0.92, "left", 1.05, "half", "Corrected"
    
    # Scale pattern visualization
    Select outer viewport: 0, 8, 5.0, 5.6
    Select inner viewport: 0.6, 7.6, 5.1, 5.5
    
    Axes: 0, 12, 0, 1
    
    noteNames$# = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
    
    for pc from 0 to 11
        # Rotate to show from root
        displayPC = (pc + root_idx) mod 12
        inScale$ = mid$(pat$, pc + 1, 1)
        
        if inScale$ = "1"
            Paint rectangle: "{0.6, 0.8, 0.6}", pc + 0.1, pc + 0.9, 0.1, 0.9
        else
            Paint rectangle: "{0.85, 0.85, 0.85}", pc + 0.1, pc + 0.9, 0.1, 0.9
        endif
        
        Colour: "Black"
        Font size: 5
        Text: pc + 0.5, "centre", 0.5, "half", noteNames$#[displayPC + 1]
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Scale"
    
    # Stats
    Select outer viewport: 0, 8, 5.7, 6.0
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Key: " + rootName$ + " " + scaleName$ + " | Strength: " + string$(strength) + "% | Corrected: " + string$(corrected_count) + "/" + string$(n) + " notes"
    
    Font size: 10
    Colour: "Black"
endif

# === Cleanup ===
removeObject: manipulation, pitchTier, correctedTier

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