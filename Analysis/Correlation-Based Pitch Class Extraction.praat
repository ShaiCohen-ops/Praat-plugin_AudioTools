# ============================================================
# Praat AudioTools - Correlation-Based_Pitch_Class_Extraction.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.6 (2025) - Added summary table
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Correlation-Based Pitch Class Extraction (Matched Filter)
#
# Changelog v0.6:
#   - Added summary table in Info window
#   - Shows note, MIDI, frequency, template duration, peak count
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") = 0
    exitScript: "Please select a Sound object first."
endif

original_sound = selected("Sound")
original_name$ = selected$("Sound")

form Correlation-Based Pitch Class Extraction v0.6
    comment === Pitch Analysis ===
    real Pitch_floor_Hz 75
    real Pitch_ceiling_Hz 600
    optionmenu Method: 1
        option Accurate (cc)
        option Standard (ac)
    comment === Target Note ===
    comment Leave MIDI=0 to extract ALL detected notes
    integer Target_MIDI_note 0
    comment Or specify note name (e.g. C4, F#3)
    word Target_note_name 
    comment === Post-processing ===
    boolean Apply_gate_function 1
    real Gate_threshold_dB -40
    boolean Normalize_result 1
    real Peak_amplitude 0.99
    comment === Output ===
    boolean Keep_templates 0
    boolean Keep_correlations 0
endform

# === Setup ===
selectObject: original_sound
duration = Get total duration
sampleRate = Get sampling frequency

clearinfo
writeInfoLine: "=== Correlation-Based Pitch Class Extraction v0.6 ==="
appendInfoLine: "Input: ", original_name$
appendInfoLine: "Duration: ", fixed$(duration, 3), " s"
appendInfoLine: ""

# ============================================================
# STEP 1: PITCH ANALYSIS
# ============================================================
appendInfoLine: "[1/6] Analyzing fundamental frequency..."
selectObject: original_sound

if method = 1
    pitch = To Pitch (cc): 0, pitch_floor_Hz, 15, "no", 0.03, 0.45, 0.01, 0.35, 0.14, pitch_ceiling_Hz
else
    pitch = To Pitch: 0, pitch_floor_Hz, pitch_ceiling_Hz
endif

# ============================================================
# STEP 2: EXTRACT DETECTED PITCHES
# ============================================================
appendInfoLine: "[2/6] Extracting detected pitches..."

selectObject: pitch
n_frames = Get number of frames

pitchCount = 0
for i from 1 to n_frames
    f0 = Get value in frame: i, "Hertz"
    if f0 <> undefined
        pitchCount = pitchCount + 1
        pitch_value_'pitchCount' = f0
        pitch_time_'pitchCount' = Get time from frame number: i
    endif
endfor

appendInfoLine: "  Found ", pitchCount, " voiced frames"

if pitchCount = 0
    removeObject: pitch
    exitScript: "No pitch detected. Try adjusting pitch floor/ceiling."
endif

# ============================================================
# STEP 3: CLUSTER PITCHES INTO NOTE CLASSES
# ============================================================
appendInfoLine: "[3/6] Clustering into note classes..."

for i from 1 to pitchCount
    pv = pitch_value_'i'
    midi_note_'i' = round(12 * log2(pv / 440) + 69)
endfor

# Find unique MIDI notes
uniqueCount = 0
for i from 1 to pitchCount
    note = midi_note_'i'
    isUnique = 1
    for j from 1 to uniqueCount
        existingNote = unique_midi_'j'
        if note = existingNote
            isUnique = 0
        endif
    endfor
    if isUnique
        uniqueCount = uniqueCount + 1
        unique_midi_'uniqueCount' = note
    endif
endfor

# Sort unique notes
for i from 1 to uniqueCount - 1
    for j from i + 1 to uniqueCount
        vi = unique_midi_'i'
        vj = unique_midi_'j'
        if vi > vj
            unique_midi_'i' = vj
            unique_midi_'j' = vi
        endif
    endfor
endfor

appendInfoLine: "  Found ", uniqueCount, " unique pitch classes"
appendInfoLine: ""

# Create note names and calculate average frequencies
for i from 1 to uniqueCount
    midi = unique_midi_'i'
    note_class = (midi - 12) mod 12
    octave = floor((midi - 12) / 12)
    
    if note_class = 0
        nn$ = "C"
    elsif note_class = 1
        nn$ = "Cs"
    elsif note_class = 2
        nn$ = "D"
    elsif note_class = 3
        nn$ = "Ds"
    elsif note_class = 4
        nn$ = "E"
    elsif note_class = 5
        nn$ = "F"
    elsif note_class = 6
        nn$ = "Fs"
    elsif note_class = 7
        nn$ = "G"
    elsif note_class = 8
        nn$ = "Gs"
    elsif note_class = 9
        nn$ = "A"
    elsif note_class = 10
        nn$ = "As"
    elsif note_class = 11
        nn$ = "B"
    endif
    
    unique_note_name_'i'$ = nn$ + string$(octave)
    
    # Display name with sharp symbol
    if note_class = 1
        display_name$ = "C#"
    elsif note_class = 3
        display_name$ = "D#"
    elsif note_class = 6
        display_name$ = "F#"
    elsif note_class = 8
        display_name$ = "G#"
    elsif note_class = 10
        display_name$ = "A#"
    else
        display_name$ = nn$
    endif
    unique_display_'i'$ = display_name$ + string$(octave)
    
    # Calculate average frequency
    count = 0
    sum = 0
    for j from 1 to pitchCount
        mn = midi_note_'j'
        if mn = midi
            count = count + 1
            pv = pitch_value_'j'
            sum = sum + pv
        endif
    endfor
    unique_freq_'i' = sum / count
endfor

# Display detected notes
appendInfoLine: "Detected notes:"
for i from 1 to uniqueCount
    dn$ = unique_display_'i'$
    midi = unique_midi_'i'
    freq = unique_freq_'i'
    appendInfoLine: "  ", dn$, " (MIDI ", midi, ", ~", fixed$(freq, 1), " Hz)"
endfor
appendInfoLine: ""

# ============================================================
# STEP 4: DETERMINE WHICH NOTES TO EXTRACT
# ============================================================
appendInfoLine: "[4/6] Determining target notes..."

extractAll = 0
if target_note_name$ <> ""
    # Parse note name to MIDI
    tn$ = replace$(target_note_name$, "#", "s", 0)
    tn$ = replace$(tn$, "♯", "s", 0)
    
    len = length(tn$)
    if len >= 2
        if len >= 3 and mid$(tn$, 2, 1) = "s"
            notePart$ = left$(tn$, 2)
            octavePart$ = right$(tn$, len - 2)
        else
            notePart$ = left$(tn$, 1)
            octavePart$ = right$(tn$, len - 1)
        endif
        
        notePart$ = replace$(notePart$, "c", "C", 0)
        notePart$ = replace$(notePart$, "d", "D", 0)
        notePart$ = replace$(notePart$, "e", "E", 0)
        notePart$ = replace$(notePart$, "f", "F", 0)
        notePart$ = replace$(notePart$, "g", "G", 0)
        notePart$ = replace$(notePart$, "a", "A", 0)
        notePart$ = replace$(notePart$, "b", "B", 0)
        
        if notePart$ = "C"
            pc = 0
        elsif notePart$ = "Cs"
            pc = 1
        elsif notePart$ = "D"
            pc = 2
        elsif notePart$ = "Ds"
            pc = 3
        elsif notePart$ = "E"
            pc = 4
        elsif notePart$ = "F"
            pc = 5
        elsif notePart$ = "Fs"
            pc = 6
        elsif notePart$ = "G"
            pc = 7
        elsif notePart$ = "Gs"
            pc = 8
        elsif notePart$ = "A"
            pc = 9
        elsif notePart$ = "As"
            pc = 10
        elsif notePart$ = "B"
            pc = 11
        else
            pc = -1
        endif
        
        if pc >= 0
            oct = number(octavePart$)
            target_MIDI_note = (oct + 1) * 12 + pc
            appendInfoLine: "  Parsed '", target_note_name$, "' as MIDI ", target_MIDI_note
        else
            extractAll = 1
        endif
    else
        extractAll = 1
    endif
elsif target_MIDI_note = 0
    extractAll = 1
    appendInfoLine: "  Extracting ALL detected notes"
else
    appendInfoLine: "  Target MIDI: ", target_MIDI_note
endif

# Build list of notes to extract
if extractAll = 1
    numToExtract = uniqueCount
    for i from 1 to uniqueCount
        extract_midi_'i' = unique_midi_'i'
        extract_name_'i'$ = unique_note_name_'i'$
        extract_display_'i'$ = unique_display_'i'$
        extract_freq_'i' = unique_freq_'i'
    endfor
else
    found = 0
    for i from 1 to uniqueCount
        if unique_midi_'i' = target_MIDI_note
            found = 1
            numToExtract = 1
            extract_midi_1 = unique_midi_'i'
            extract_name_1$ = unique_note_name_'i'$
            extract_display_1$ = unique_display_'i'$
            extract_freq_1 = unique_freq_'i'
        endif
    endfor
    
    if found = 0
        removeObject: pitch
        exitScript: "Target note not found. See Info window for available notes."
    endif
endif

appendInfoLine: "  Will extract ", numToExtract, " note(s)"
appendInfoLine: ""

# ============================================================
# STEP 5: EXTRACT EACH TARGET NOTE
# ============================================================

numExtracted = 0

for n from 1 to numToExtract
    targetMidi = extract_midi_'n'
    targetName$ = extract_name_'n'$
    targetFreq = extract_freq_'n'
    
    appendInfoLine: "[5/6] Processing ", targetName$, " (MIDI ", targetMidi, ")..."
    
    # Find longest continuous segment
    best_start = 0
    best_end = 0
    best_duration = 0
    current_start_idx = 0
    in_segment = 0
    
    for i from 1 to pitchCount
        mn = midi_note_'i'
        if mn = targetMidi
            if in_segment = 0
                current_start_idx = i
                in_segment = 1
            endif
        else
            if in_segment = 1
                iPrev = i - 1
                startT = pitch_time_'current_start_idx'
                endT = pitch_time_'iPrev'
                segDur = endT - startT
                if segDur > best_duration
                    best_duration = segDur
                    best_start = startT
                    best_end = endT
                endif
                in_segment = 0
            endif
        endif
    endfor
    
    if in_segment = 1
        startT = pitch_time_'current_start_idx'
        endT = pitch_time_'pitchCount'
        segDur = endT - startT
        if segDur > best_duration
            best_duration = segDur
            best_start = startT
            best_end = endT
        endif
    endif
    
    if best_duration > 0
        padding = 0.05
        template_start = max(0, best_start - padding)
        template_end = min(duration, best_end + padding)
        templateDur = template_end - template_start
        
        # Extract template
        selectObject: original_sound
        template = Extract part: template_start, template_end, "rectangular", 1.0, "no"
        Rename: original_name$ + "_" + targetName$ + "_template"
        
        # Cross-correlation
        selectObject: original_sound
        plusObject: template
        corr = Cross-correlate: "peak 0.99", "zero"
        Rename: original_name$ + "_" + targetName$ + "_corr"
        
        selectObject: corr
        corr_max = Get maximum: 0, 0, "None"
        
        # Gate and create result
        if apply_gate_function
            threshold_linear = 10^(gate_threshold_dB / 20) * corr_max
            threshLin$ = string$(threshold_linear)
            result = Copy: original_name$ + "_" + targetName$ + "_result"
            Formula: "if abs(self) < " + threshLin$ + " then 0 else self endif"
        else
            result = Copy: original_name$ + "_" + targetName$ + "_result"
        endif
        
        # Normalize
        if normalize_result
            selectObject: result
            Scale peak: peak_amplitude
        endif
        
        # Count peaks in result (simple zero-crossing count for positive peaks)
        selectObject: result
        resultDur = Get total duration
        peakCount = 0
        wasAbove = 0
        peakThreshold = 0.1 * peak_amplitude
        
        # Sample at ~100 Hz for peak detection
        stepSize = 0.01
        t = 0
        while t < resultDur
            val = Get value at time: 1, t, "Sinc70"
            if val = undefined
                val = 0
            endif
            
            if val > peakThreshold
                if wasAbove = 0
                    peakCount = peakCount + 1
                    wasAbove = 1
                endif
            else
                wasAbove = 0
            endif
            t = t + stepSize
        endwhile
        
        # Store data for summary
        numExtracted = numExtracted + 1
        result_'numExtracted' = result
        summary_display_'numExtracted'$ = extract_display_'n'$
        summary_midi_'numExtracted' = targetMidi
        summary_freq_'numExtracted' = targetFreq
        summary_templDur_'numExtracted' = templateDur
        summary_peaks_'numExtracted' = peakCount
        
        # Cleanup intermediate objects
        if keep_templates = 0
            removeObject: template
        else
            template_'numExtracted' = template
        endif
        
        if keep_correlations = 0
            removeObject: corr
        else
            corr_'numExtracted' = corr
        endif
        
    else
        appendInfoLine: "  WARNING: No continuous segment found, skipping"
    endif
endfor

# ============================================================
# CLEANUP
# ============================================================
appendInfoLine: ""
appendInfoLine: "[6/6] Cleaning up..."
removeObject: pitch

# ============================================================
# SUMMARY TABLE
# ============================================================
appendInfoLine: ""
appendInfoLine: "============================================================"
appendInfoLine: "SUMMARY"
appendInfoLine: "============================================================"
appendInfoLine: ""
appendInfoLine: "Note      MIDI    Avg Hz    Template    Peaks"
appendInfoLine: "----      ----    ------    --------    -----"

for n from 1 to numExtracted
    dn$ = summary_display_'n'$
    midi = summary_midi_'n'
    freq = summary_freq_'n'
    tDur = summary_templDur_'n'
    peaks = summary_peaks_'n'
    
    # Pad note name to 8 chars
    while length(dn$) < 8
        dn$ = dn$ + " "
    endwhile
    
    # Format MIDI (4 chars)
    midi$ = string$(midi)
    while length(midi$) < 4
        midi$ = midi$ + " "
    endwhile
    
    # Format frequency (8 chars)
    freq$ = fixed$(freq, 1)
    while length(freq$) < 8
        freq$ = freq$ + " "
    endwhile
    
    # Format template duration (8 chars)
    tDur$ = fixed$(tDur * 1000, 0) + " ms"
    while length(tDur$) < 10
        tDur$ = tDur$ + " "
    endwhile
    
    appendInfoLine: dn$, "  ", midi$, "    ", freq$, "  ", tDur$, "  ", peaks
endfor

appendInfoLine: ""
appendInfoLine: "============================================================"
appendInfoLine: "Total: ", numExtracted, " notes extracted"
appendInfoLine: "============================================================"

# ============================================================
# OUTPUT
# ============================================================
if numExtracted > 0
    selectObject: result_1
    for n from 2 to numExtracted
        plusObject: result_'n'
    endfor
    
    if keep_templates
        for n from 1 to numExtracted
            plusObject: template_'n'
        endfor
    endif
    
    if keep_correlations
        for n from 1 to numExtracted
            plusObject: corr_'n'
        endfor
    endif
else
    selectObject: original_sound
    appendInfoLine: "No notes extracted."
endif
