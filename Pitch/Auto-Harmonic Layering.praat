# ============================================================
# Praat AudioTools - Auto-Harmonic_Layering.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Auto-Harmonic Layering - automatically detects repeating
#   loops using Self-Similarity Matrix analysis, then generates
#   harmonized versions (pitch-shifted copies forming chords).
#   Dry signal stays centered, harmonies split to stereo field.
#
# Changelog v0.3:
#   - Dry centered and louder, wet split to stereo
#   - Added visualization
#   - Fixed dynamic variable syntax (arrays)
# ============================================================

form Auto-Harmonic Layering
    comment Select a Sound object first
    
    comment === Loop Detection ===
    positive Time_step 0.05
    positive Pitch_floor 75
    positive Pitch_ceiling 600
    positive Tolerance_hz 50
    positive Min_loop_duration 0.4
    positive Max_loop_duration 10.0
    integer Num_loops_to_find 5

    comment === Harmonization ===
    optionmenu Chord_Type 7
        option Octave Doubling
        option Fifth
        option Major
        option Minor
        option Sus4
        option Sus2
        option Random
    
    comment === Mixing ===
    real Dry_level 0.8
    real Wet_level 0.5
    real Stereo_spread 0.7
    comment (0 = mono center, 1 = hard L/R)
    
    comment === Scope ===
    boolean Harmonize_repeats 1
    real Harmonize_until_time 0
    
    comment === Chord Levels (0-1) ===
    real Root_level 1.0
    real Note_2_level 0.8
    real Note_3_level 0.6
    
    comment === Envelope ===
    positive Fade_duration 0.01
    boolean Apply_fades 1
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ===================================================================
# PHASE 1: FIND LOOPS
# ===================================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

selectObject: originalID
total_duration = Get total duration
original_sr = Get sampling frequency

writeInfoLine: "=== AUTO-HARMONIC LAYERING ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(total_duration, 2), " s)"
appendInfoLine: ""
appendInfoLine: "--- Phase 1: Analyzing Pitch & Loops ---"

# 1. Extract Pitch
selectObject: originalID
To Pitch: time_step, pitch_floor, pitch_ceiling
pitchID = selected("Pitch")
num_frames = Get number of frames

# 2. Convert Pitch to Matrix
Create simple Matrix: "ThePitchData", num_frames, 1, "0"
dataID = selected("Matrix")

selectObject: pitchID
pitch_vals# = zero#(num_frames)
for i to num_frames
    val = Get value in frame: i, "Hertz"
    if val = undefined
        val = 0
    endif
    pitch_vals#[i] = val
endfor
removeObject: pitchID

selectObject: dataID
for i to num_frames
    Set value: i, 1, pitch_vals#[i]
endfor

# 3. Calculate SSM
appendInfoLine: "Building self-similarity matrix..."
Create simple Matrix: "SSM", num_frames, num_frames, "0"
ssmID = selected("Matrix")

Formula: "if Matrix_ThePitchData[row, 1] > 0 and Matrix_ThePitchData[col, 1] > 0 and abs(Matrix_ThePitchData[row, 1] - Matrix_ThePitchData[col, 1]) < " + string$(tolerance_hz) + " then 1 - (abs(Matrix_ThePitchData[row, 1] - Matrix_ThePitchData[col, 1]) / " + string$(tolerance_hz) + ") else 0 fi"

# 4. Find Candidates
selectObject: originalID
To TextGrid: "Loops Repeats", ""
textgridID = selected("TextGrid")

Create Table with column names: "candidates", 0, "start_frame length_frames gap_frames score"
tableID = selected("Table")

selectObject: ssmID
frame_rate = 1 / time_step
min_len = round(min_loop_duration * frame_rate)
max_gap = num_frames - min_len
gap = min_len
step = 1

if num_frames > 2000
    step = 2
endif

appendInfoLine: "Searching for loop candidates..."

while gap <= max_gap
    path_len = 0
    path_start = 0
    search_limit = num_frames - gap
    
    for i to search_limit
        j = i + gap
        val = Get value in cell: i, j
        
        if val > 0.5
            if path_len = 0
                path_start = i
            endif
            path_len = path_len + 1
        else
            if path_len >= min_len
                selectObject: tableID
                Append row
                row = Get number of rows
                Set numeric value: row, "start_frame", path_start
                Set numeric value: row, "length_frames", path_len
                Set numeric value: row, "gap_frames", gap
                Set numeric value: row, "score", path_len * val
                selectObject: ssmID
            endif
            path_len = 0
        endif
    endfor
    gap = gap + step
endwhile

# 5. Filter & Annotate
selectObject: tableID
nRows = Get number of rows

if nRows = 0
    removeObject: dataID, ssmID, tableID, textgridID
    exitScript: "No loops found. Try adjusting tolerance or loop duration."
endif

Sort rows: "score"

# Arrays for loop timing (for visualization)
maxLoops = num_loops_to_find
saved_t1# = zero#(maxLoops)
saved_t2# = zero#(maxLoops)
saved_rep_t1# = zero#(maxLoops)
saved_rep_t2# = zero#(maxLoops)

for k to maxLoops
    saved_t1#[k] = -1
    saved_t2#[k] = -1
    saved_rep_t1#[k] = -1
    saved_rep_t2#[k] = -1
endfor

loops_found = 0
row_index = nRows

while loops_found < num_loops_to_find and row_index > 0
    selectObject: tableID
    start_f = Get value: row_index, "start_frame"
    len_f = Get value: row_index, "length_frames"
    gap_f = Get value: row_index, "gap_frames"
    
    t1 = (start_f - 1) * time_step
    dur = len_f * time_step
    t2 = t1 + dur
    rep_t1 = (start_f + gap_f - 1) * time_step
    rep_t2 = rep_t1 + dur
    
    is_overlap = 0
    for k to loops_found
        if t1 < saved_t2#[k] and t2 > saved_t1#[k]
            is_overlap = 1
        endif
    endfor
    
    if is_overlap = 0
        loops_found = loops_found + 1
        saved_t1#[loops_found] = t1
        saved_t2#[loops_found] = t2
        saved_rep_t1#[loops_found] = rep_t1
        saved_rep_t2#[loops_found] = rep_t2
        
        selectObject: textgridID
        
        # Tier 1: Loops
        Insert boundary: 1, t1
        Insert boundary: 1, t2
        int_idx = Get interval at time: 1, t1 + 0.001
        Set interval text: 1, int_idx, "Loop " + string$(loops_found)
        
        # Tier 2: Repeats
        Insert boundary: 2, rep_t1
        Insert boundary: 2, rep_t2
        int_idx = Get interval at time: 2, rep_t1 + 0.001
        Set interval text: 2, int_idx, "Repeat " + string$(loops_found)
    endif
    row_index = row_index - 1
endwhile

appendInfoLine: "Found ", loops_found, " loops"

# CLEANUP Phase 1
removeObject: dataID, ssmID, tableID

# ===================================================================
# PHASE 1B: ASSIGN CHORD TYPES TO EACH LOOP NUMBER
# ===================================================================

chord_for_loop# = zero#(loops_found)
chord_names$# = empty$#(loops_found)

for loop_num to loops_found
    if chord_Type = 7
        chord_for_loop#[loop_num] = randomInteger(1, 6)
    else
        chord_for_loop#[loop_num] = chord_Type
    endif
    
    # Store chord name for visualization
    c = chord_for_loop#[loop_num]
    if c = 1
        chord_names$#[loop_num] = "Oct"
    elsif c = 2
        chord_names$#[loop_num] = "5th"
    elsif c = 3
        chord_names$#[loop_num] = "Maj"
    elsif c = 4
        chord_names$#[loop_num] = "Min"
    elsif c = 5
        chord_names$#[loop_num] = "Sus4"
    else
        chord_names$#[loop_num] = "Sus2"
    endif
endfor

# Report chord assignments
appendInfoLine: ""
appendInfoLine: "Chord assignments:"
for loop_num to loops_found
    appendInfoLine: "  Loop ", loop_num, ": ", chord_names$#[loop_num], " (", fixed$(saved_t1#[loop_num], 2), "-", fixed$(saved_t2#[loop_num], 2), "s)"
endfor

# ===================================================================
# PHASE 2: HARMONIZATION - OVERLAY METHOD (aligned)
# ===================================================================

appendInfoLine: ""
appendInfoLine: "--- Phase 2: Generating Harmonies ---"

# Set harmonization end time
if harmonize_until_time <= 0
    harm_end_time = total_duration
else
    harm_end_time = min(harmonize_until_time, total_duration)
endif

appendInfoLine: "Harmonizing until: ", fixed$(harm_end_time, 2), " s"

# 1. Auto-Mono Conversion for processing
selectObject: originalID
nChans = Get number of channels
if nChans > 1
    soundID = Convert to mono
    Rename: "Mono_Source"
else
    soundID = Copy: "Mono_Source"
endif

selectObject: soundID
fs = Get sampling frequency

# 2. Create FULL-DURATION wet tracks (silence)
Create Sound from formula: "wet_L", 1, 0, total_duration, fs, "0"
wetLeftID = selected("Sound")

Create Sound from formula: "wet_R", 1, 0, total_duration, fs, "0"
wetRightID = selected("Sound")

# 3. Collect Events
selectObject: textgridID
nTiers = Get number of tiers
nEvents = 0
skipped_events = 0

maxEvents = 100
event_start# = zero#(maxEvents)
event_end# = zero#(maxEvents)
event_chord# = zero#(maxEvents)

for t to nTiers
    nInt = Get number of intervals: t
    for i to nInt
        lab$ = Get label of interval: t, i
        
        is_loop = startsWith(lab$, "Loop")
        is_repeat = startsWith(lab$, "Repeat")
        
        if is_loop or is_repeat
            event_start_time = Get start point: t, i
            event_end_time = Get end point: t, i
            
            should_include = 1
            
            if is_repeat and not harmonize_repeats
                should_include = 0
            endif
            
            if event_start_time >= harm_end_time
                should_include = 0
            endif
            
            if should_include and nEvents < maxEvents
                nEvents = nEvents + 1
                event_start#[nEvents] = event_start_time
                event_end#[nEvents] = min(event_end_time, harm_end_time)
                
                if is_loop
                    loop_num_str$ = replace$(lab$, "Loop ", "", 1)
                else
                    loop_num_str$ = replace$(lab$, "Repeat ", "", 1)
                endif
                loop_num = number(loop_num_str$)
                
                event_chord#[nEvents] = chord_for_loop#[loop_num]
            else
                skipped_events = skipped_events + 1
            endif
        endif
    endfor
endfor

if skipped_events > 0
    appendInfoLine: "Skipped ", skipped_events, " events"
endif

appendInfoLine: "Processing ", nEvents, " events..."

# 4. Process each event and OVERLAY at correct position
for ev to nEvents
    evStart = event_start#[ev]
    evEnd = event_end#[ev]
    evDur = evEnd - evStart
    
    # Extract source segment
    selectObject: soundID
    Extract part: evStart, evEnd, "rectangular", 1, "no"
    clipID = selected("Sound")
    
    # Generate stereo chord
    chordType = event_chord#[ev]
    @generateChordStereo: clipID, chordType, stereo_spread
    partLeftID = generateChordStereo.leftOut
    partRightID = generateChordStereo.rightOut
    
    # Apply fades
    if apply_fades
        selectObject: partLeftID
        partDur = Get total duration
        fade_in = min(fade_duration, partDur / 4)
        fade_out = min(fade_duration, partDur / 4)
        Fade in: 0, 0, fade_in, "yes"
        Fade out: 0, partDur, -fade_out, "yes"
        
        selectObject: partRightID
        Fade in: 0, 0, fade_in, "yes"
        Fade out: 0, partDur, -fade_out, "yes"
    endif
    
    # Scale wet level
    selectObject: partLeftID
    Formula: ~ self * wet_level
    selectObject: partRightID
    Formula: ~ self * wet_level
    
    # Get the actual processed duration (may differ slightly from source)
    selectObject: partLeftID
    procDur = Get total duration
    
    # Calculate sample positions for overlay
    startSample = round(evStart * fs) + 1
    endSample = startSample + round(procDur * fs) - 1
    
    # Ensure we don't exceed track length
    selectObject: wetLeftID
    totalSamples = Get number of samples
    if endSample > totalSamples
        endSample = totalSamples
    endif
    
    # OVERLAY left channel at correct position
    selectObject: wetLeftID
    Formula (part): evStart, evStart + procDur, 1, 1, ~ self + Sound_left_mix[col - startSample + 1]
    
    # OVERLAY right channel at correct position
    selectObject: wetRightID
    Formula (part): evStart, evStart + procDur, 1, 1, ~ self + Sound_right_mix[col - startSample + 1]
    
    # Cleanup this iteration
    removeObject: clipID, partLeftID, partRightID
    
    if ev mod 5 = 0
        appendInfoLine: "  Processed event ", ev, "/", nEvents
    endif
endfor

# Combine wet L/R to stereo
selectObject: wetLeftID, wetRightID
wetStereo = Combine to stereo
Rename: "Wet_Stereo"
removeObject: wetLeftID, wetRightID

# ===================================================================
# PHASE 3: FINAL MIX - DRY CENTER + WET STEREO
# ===================================================================

appendInfoLine: ""
appendInfoLine: "--- Phase 3: Final Mix ---"

# Create dry stereo (centered in both channels)
selectObject: soundID
dryStereo = Convert to stereo
Rename: "Dry_Stereo"
Scale peak: dry_level

# Extract all 4 channels for mixing
selectObject: dryStereo
Extract one channel: 1
dryL = selected("Sound")
Rename: "dry_L"

selectObject: dryStereo
Extract one channel: 2
dryR = selected("Sound")
Rename: "dry_R"

selectObject: wetStereo
Extract one channel: 1
wetL = selected("Sound")
Rename: "wetmix_L"

selectObject: wetStereo
Extract one channel: 2
wetR = selected("Sound")
Rename: "wetmix_R"

# Mix: dry + wet for each channel
selectObject: dryL
Formula: ~ self + Sound_wetmix_L[]

selectObject: dryR
Formula: ~ self + Sound_wetmix_R[]

# Combine to final stereo
selectObject: dryL, dryR
Combine to stereo
finalID = selected("Sound")
Rename: originalName$ + "_harmonized"
Scale peak: 0.95

# ===================================================================
# CLEANUP
# ===================================================================

removeObject: textgridID, soundID
removeObject: wetStereo, dryStereo
removeObject: dryL, dryR, wetL, wetR

# ===================================================================
# VISUALIZATION
# ===================================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Auto-Harmonic Layering: " + originalName$
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.7
    Select inner viewport: 0.6, 7.6, 0.7, 1.6
    selectObject: originalID
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform (stereo)
    Select outer viewport: 0, 8, 1.8, 2.9
    Select inner viewport: 0.6, 7.6, 1.9, 2.8
    selectObject: finalID
    Colour: "{0.5, 0.6, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Harmonized"
    Text bottom: "yes", "Time (s)"
    
    # Loop detection visualization
    Select outer viewport: 0, 8, 3.1, 4.5
    Select inner viewport: 0.6, 7.6, 3.3, 4.4
    
    Axes: 0, total_duration, 0, 3
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, total_duration, 0, 3
    
    # Draw loops (tier 1)
    for lp to loops_found
        if saved_t1#[lp] >= 0
            # Loop region (blue)
            Paint rectangle: "{0.5, 0.7, 0.9}", saved_t1#[lp], saved_t2#[lp], 1.6, 2.8
            
            # Repeat region (orange)
            if saved_rep_t1#[lp] >= 0 and saved_rep_t1#[lp] < total_duration
                Paint rectangle: "{0.9, 0.7, 0.5}", saved_rep_t1#[lp], min(saved_rep_t2#[lp], total_duration), 0.2, 1.4
            endif
            
            # Chord label
            Colour: "Black"
            Font size: 6
            midLoop = (saved_t1#[lp] + saved_t2#[lp]) / 2
            Text: midLoop, "centre", 2.2, "half", chord_names$#[lp]
            Text: midLoop, "centre", 2.6, "half", string$(lp)
        endif
    endfor
    
    # Labels
    Colour: "Black"
    Font size: 7
    Text: 0.02, "left", 2.2, "half", "Loops"
    Text: 0.02, "left", 0.8, "half", "Repeats"
    
    Colour: "Black"
    Draw inner box
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Detected"
    
    # Chord legend
    Select outer viewport: 0, 8, 4.6, 5.0
    Select inner viewport: 0.6, 7.6, 4.7, 4.95
    
    Axes: 0, 6, 0, 1
    
    # Draw chord type boxes
    chordLabels$# = {"Oct", "5th", "Maj", "Min", "Sus4", "Sus2"}
    chordColors$# = {"{0.8,0.6,0.6}", "{0.6,0.8,0.6}", "{0.6,0.6,0.8}", "{0.8,0.6,0.8}", "{0.8,0.8,0.6}", "{0.6,0.8,0.8}"}
    
    for c to 6
        Paint rectangle: chordColors$#[c], c - 0.9, c - 0.1, 0.2, 0.8
        Colour: "Black"
        Font size: 6
        Text: c - 0.5, "centre", 0.5, "half", chordLabels$#[c]
    endfor
    
    Colour: "Black"
    Font size: 7
    Text left: "yes", "Chords"
    
    # Stats
    Select outer viewport: 0, 8, 5.1, 5.4
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Loops: " + string$(loops_found) + " | Events: " + string$(nEvents) + " | Dry: " + fixed$(dry_level, 2) + " (center) | Wet: " + fixed$(wet_level, 2) + " (spread " + fixed$(stereo_spread, 2) + ")"
    
    Font size: 10
    Colour: "Black"
endif

# ===================================================================
# FINAL OUTPUT
# ===================================================================

selectObject: finalID

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Loops: ", loops_found
appendInfoLine: "Events harmonized: ", nEvents

if play_result
    selectObject: finalID
    Play
endif

selectObject: finalID

# ===================================================================
# PROCEDURE: Generate Chord with Stereo Split
# ===================================================================
procedure generateChordStereo: .srcID, .type, .spread
    selectObject: .srcID
    .fs = Get sampling frequency
    
    # Interval Definitions (Semitones)
    if .type = 1
        .i2 = 12
        .i3 = 24
    elsif .type = 2
        .i2 = 7
        .i3 = 12
    elsif .type = 3
        .i2 = 4
        .i3 = 7
    elsif .type = 4
        .i2 = 3
        .i3 = 7
    elsif .type = 5
        .i2 = 5
        .i3 = 7
    else
        .i2 = 2
        .i3 = 7
    endif
    
    .semitone = 2 ^ (1/12)
    
    # 1. Root (center - goes to both)
    selectObject: .srcID
    .root = Copy: "root"
    Scale peak: root_level
    
    # 2. Note 2 (will go more to LEFT)
    selectObject: .srcID
    .n2 = Copy: "n2"
    .ratio = .semitone ^ .i2
    Override sampling frequency: .fs * .ratio
    .m = To Manipulation: 0.01, 75, 600
    .d = Extract duration tier
    selectObject: .d
    Add point: 0, .ratio
    selectObject: .m, .d
    Replace duration tier
    selectObject: .m
    .res2 = Get resynthesis (overlap-add)
    selectObject: .res2
    .note2 = Resample: .fs, 50
    Scale peak: note_2_level
    removeObject: .n2, .m, .d, .res2
    
    # 3. Note 3 (will go more to RIGHT)
    selectObject: .srcID
    .n3 = Copy: "n3"
    .ratio = .semitone ^ .i3
    Override sampling frequency: .fs * .ratio
    .m = To Manipulation: 0.01, 75, 600
    .d = Extract duration tier
    selectObject: .d
    Add point: 0, .ratio
    selectObject: .m, .d
    Replace duration tier
    selectObject: .m
    .res3 = Get resynthesis (overlap-add)
    selectObject: .res3
    .note3 = Resample: .fs, 50
    Scale peak: note_3_level
    removeObject: .n3, .m, .d, .res3
    
    # 4. Create stereo panning
    # Left channel: root + more note2 + less note3
    # Right channel: root + less note2 + more note3
    
    .leftGain2 = 1 - .spread * 0.5
    .rightGain2 = .spread * 0.5
    .leftGain3 = .spread * 0.5
    .rightGain3 = 1 - .spread * 0.5
    
    # Build LEFT channel
    selectObject: .root
    .rootCopyL = Copy: "rootL"
    
    selectObject: .note2
    .note2L = Copy: "note2L"
    Formula: ~ self * .leftGain2
    
    selectObject: .note3
    .note3L = Copy: "note3L"
    Formula: ~ self * .leftGain3
    
    # Mix left
    selectObject: .rootCopyL, .note2L
    .tmpL1 = Combine to stereo
    .mixL1 = Convert to mono
    removeObject: .tmpL1
    
    selectObject: .mixL1, .note3L
    .tmpL2 = Combine to stereo
    .leftOut = Convert to mono
    Rename: "left_mix"
    removeObject: .tmpL2, .mixL1, .rootCopyL, .note2L, .note3L
    
    # Build RIGHT channel
    selectObject: .root
    .rootCopyR = Copy: "rootR"
    
    selectObject: .note2
    .note2R = Copy: "note2R"
    Formula: ~ self * .rightGain2
    
    selectObject: .note3
    .note3R = Copy: "note3R"
    Formula: ~ self * .rightGain3
    
    # Mix right
    selectObject: .rootCopyR, .note2R
    .tmpR1 = Combine to stereo
    .mixR1 = Convert to mono
    removeObject: .tmpR1
    
    selectObject: .mixR1, .note3R
    .tmpR2 = Combine to stereo
    .rightOut = Convert to mono
    Rename: "right_mix"
    removeObject: .tmpR2, .mixR1, .rootCopyR, .note2R, .note3R
    
    # Cleanup
    removeObject: .root, .note2, .note3
    
    # Return via procedure variables
    .leftOut = .leftOut
    .rightOut = .rightOut
endproc
