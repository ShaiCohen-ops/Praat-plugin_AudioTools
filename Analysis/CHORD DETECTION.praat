# ============================================================
# Praat AudioTools - CHORD_DETECTION.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025) - Fixed and enhanced
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Chord Detection - Analyzes audio to detect chords using
#   spectral peak analysis and pattern matching against a
#   comprehensive chord dictionary.
#
# Usage:
#   Select a Sound object in Praat and run this script.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.3:
#   - Fixed procedure call syntax (call -> @)
#   - Fixed != to <> operator
#   - Fixed negative pitch class handling
#   - Added input validation
#   - Added presets
#   - Added visualization
#   - Fixed plus syntax
# ============================================================

# Input validation
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
sound_name$ = selected$("Sound")

form Chord Detection v0.3
    comment === Presets ===
    optionmenu Preset: 1
        option Custom
        option Quick Scan (fast rough detection)
        option Standard Analysis (balanced)
        option Fine Detail (slow precise)
        option Polyphonic Dense (many notes)
        option Monophonic Melody (single line)
    comment === Time Analysis ===
    positive Window_size_ms 100
    positive Time_step_ms 50
    positive Skip_transient_ms 10
    comment === Frequency Analysis ===
    positive Min_frequency_Hz 80
    positive Max_frequency_Hz 2000
    comment === Peak Detection ===
    positive Min_peak_separation_Hz 40
    positive Harmonic_tolerance_cents 75
    boolean Remove_harmonic_duplicates 1
    positive Max_peaks_to_keep 4
    comment === Output ===
    positive Min_chord_duration_ms 200
    boolean Show_all_detections 0
    boolean Draw_visualization 1
endform

# Apply presets
if preset = 2
    # Quick Scan
    window_size_ms = 150
    time_step_ms = 100
    skip_transient_ms = 20
    min_frequency_Hz = 100
    max_frequency_Hz = 1500
    min_peak_separation_Hz = 50
    harmonic_tolerance_cents = 100
    max_peaks_to_keep = 3
    min_chord_duration_ms = 300
    presetName$ = "QuickScan"
elsif preset = 3
    # Standard Analysis
    window_size_ms = 100
    time_step_ms = 50
    skip_transient_ms = 10
    min_frequency_Hz = 80
    max_frequency_Hz = 2000
    min_peak_separation_Hz = 40
    harmonic_tolerance_cents = 75
    max_peaks_to_keep = 4
    min_chord_duration_ms = 200
    presetName$ = "Standard"
elsif preset = 4
    # Fine Detail
    window_size_ms = 80
    time_step_ms = 25
    skip_transient_ms = 5
    min_frequency_Hz = 60
    max_frequency_Hz = 3000
    min_peak_separation_Hz = 30
    harmonic_tolerance_cents = 50
    max_peaks_to_keep = 6
    min_chord_duration_ms = 100
    presetName$ = "FineDetail"
elsif preset = 5
    # Polyphonic Dense
    window_size_ms = 120
    time_step_ms = 60
    skip_transient_ms = 10
    min_frequency_Hz = 60
    max_frequency_Hz = 2500
    min_peak_separation_Hz = 25
    harmonic_tolerance_cents = 60
    max_peaks_to_keep = 8
    min_chord_duration_ms = 150
    presetName$ = "Polyphonic"
elsif preset = 6
    # Monophonic Melody
    window_size_ms = 50
    time_step_ms = 25
    skip_transient_ms = 5
    min_frequency_Hz = 80
    max_frequency_Hz = 1000
    min_peak_separation_Hz = 80
    harmonic_tolerance_cents = 100
    max_peaks_to_keep = 1
    min_chord_duration_ms = 50
    presetName$ = "Monophonic"
else
    presetName$ = "Custom"
endif

# Convert to seconds
window_size = window_size_ms / 1000
time_step = time_step_ms / 1000
skip_transient = skip_transient_ms / 1000
min_chord_duration = min_chord_duration_ms / 1000

selectObject: sound
duration = Get total duration
sampling_rate = Get sampling frequency

clearinfo
writeInfoLine: "=== CHORD DETECTION v0.3 ==="
appendInfoLine: "Sound: ", sound_name$
appendInfoLine: "Duration: ", fixed$(duration, 3), " s"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""

# Create TextGrid
selectObject: sound
textgrid = To TextGrid: "chords notes", ""

analysis_time = skip_transient
frame_number = 0

previous_chord$ = ""
current_chord_start = 0
current_chord$ = ""

# Store chord history for visualization
max_history = 100
n_chord_history = 0

appendInfoLine: "Analyzing..."

while analysis_time < (duration - window_size)
    frame_number += 1
    
    selectObject: sound
    start_time = analysis_time
    end_time = analysis_time + window_size
    
    extract = Extract part: start_time, end_time, "rectangular", 1.0, "no"
    spectrum = To Spectrum: "no"
    
    selectObject: spectrum
    n_bins = Get number of bins
    
    n_peaks = 0
    max_power_db = -999
    
    # Find maximum power in range
    for i_bin from 1 to n_bins
        freq = Get frequency from bin number: i_bin
        
        if freq >= min_frequency_Hz and freq <= max_frequency_Hz
            real_val = Get real value in bin: i_bin
            imag_val = Get imaginary value in bin: i_bin
            power = sqrt(real_val^2 + imag_val^2)
            
            if power > 0
                power_db = 20 * log10(power)
            else
                power_db = -999
            endif
            
            if power_db > max_power_db
                max_power_db = power_db
            endif
        endif
    endfor
    
    relative_threshold_db = 25
    effective_threshold = max_power_db - relative_threshold_db
    
    # Peak detection
    for i_bin from 2 to n_bins - 1
        freq = Get frequency from bin number: i_bin
        
        if freq >= min_frequency_Hz and freq <= max_frequency_Hz
            real_val = Get real value in bin: i_bin
            imag_val = Get imaginary value in bin: i_bin
            power = sqrt(real_val^2 + imag_val^2)
            
            power_db = -999
            if power > 0
                power_db = 20 * log10(power)
            endif
            
            if power_db >= effective_threshold
                real_prev = Get real value in bin: i_bin - 1
                imag_prev = Get imaginary value in bin: i_bin - 1
                power_prev = sqrt(real_prev^2 + imag_prev^2)
                
                power_prev_db = -999
                if power_prev > 0
                    power_prev_db = 20 * log10(power_prev)
                endif
                
                real_next = Get real value in bin: i_bin + 1
                imag_next = Get imaginary value in bin: i_bin + 1
                power_next = sqrt(real_next^2 + imag_next^2)
                
                power_next_db = -999
                if power_next > 0
                    power_next_db = 20 * log10(power_next)
                endif
                
                is_peak = 0
                if power_db > power_prev_db and power_db > power_next_db
                    is_peak = 1
                endif
                
                if is_peak
                    too_close = 0
                    for i_check from 1 to n_peaks
                        freq_diff = abs(freq - peak_freq_'i_check')
                        if freq_diff < min_peak_separation_Hz
                            if power_db > peak_power_'i_check'
                                peak_freq_'i_check' = freq
                                peak_power_'i_check' = power_db
                            endif
                            too_close = 1
                        endif
                    endfor
                    
                    if not too_close
                        n_peaks += 1
                        peak_freq_'n_peaks' = freq
                        peak_power_'n_peaks' = power_db
                    endif
                endif
            endif
        endif
    endfor
    
    # Keep only strongest peaks (bubble sort descending)
    if n_peaks > max_peaks_to_keep
        for i from 1 to n_peaks - 1
            for j from 1 to n_peaks - i
                j_plus_1 = j + 1
                power_j = peak_power_'j'
                power_j_plus_1 = peak_power_'j_plus_1'
                
                if power_j < power_j_plus_1
                    temp_freq = peak_freq_'j'
                    peak_freq_'j' = peak_freq_'j_plus_1'
                    peak_freq_'j_plus_1' = temp_freq
                    
                    temp_power = peak_power_'j'
                    peak_power_'j' = peak_power_'j_plus_1'
                    peak_power_'j_plus_1' = temp_power
                endif
            endfor
        endfor
        n_peaks = max_peaks_to_keep
    endif
    
    # Convert to notes
    n_notes = 0
    notes_list$ = ""
    
    for i_peak from 1 to n_peaks
        freq = peak_freq_'i_peak'
        power = peak_power_'i_peak'
        
        midi_note = 69 + 12 * (ln(freq/440) / ln(2))
        midi_rounded = round(midi_note)
        pitch_class = midi_rounded mod 12
        # Fix negative pitch class
        if pitch_class < 0
            pitch_class = pitch_class + 12
        endif
        
        n_notes += 1
        note_freq_'n_notes' = freq
        note_midi_'n_notes' = midi_rounded
        note_power_'n_notes' = power
        note_pitch_class_'n_notes' = pitch_class
        
        @pitchClassToName: pitch_class
        if i_peak > 1
            notes_list$ = notes_list$ + " "
        endif
        notes_list$ = notes_list$ + pitchClassToName.result$
    endfor
    
    # Harmonic removal
    if remove_harmonic_duplicates and n_notes > 1
        for i from 1 to n_notes
            note_keep_'i' = 1
        endfor
        
        for i from 1 to n_notes
            current_freq = note_freq_'i'
            current_power = note_power_'i'
            
            for j from 1 to n_notes
                if j <> i
                    if note_power_'j' > current_power
                        fundamental_freq = note_freq_'j'
                        
                        for harmonic from 2 to 6
                            expected_harmonic = fundamental_freq * harmonic
                            freq_ratio = current_freq / expected_harmonic
                            cents_diff = 1200 * abs(ln(freq_ratio) / ln(2))
                            
                            if cents_diff < harmonic_tolerance_cents
                                note_keep_'i' = 0
                            endif
                        endfor
                    endif
                endif
            endfor
        endfor
        
        n_notes_filtered = 0
        for i from 1 to n_notes
            if note_keep_'i' = 1
                n_notes_filtered += 1
                note_pitch_class_filtered_'n_notes_filtered' = note_pitch_class_'i'
            endif
        endfor
        
        n_notes = n_notes_filtered
        for i from 1 to n_notes
            note_pitch_class_'i' = note_pitch_class_filtered_'i'
        endfor
    endif
    
    # Build chord name
    chord_name$ = ""
    
    if n_notes >= 2
        @createPitchClassSet: n_notes
        pc_set_size = createPitchClassSet.n
        @matchChord: pc_set_size
        chord_name$ = matchChord.result$
    elsif n_notes = 1
        @pitchClassToName: note_pitch_class_1
        chord_name$ = pitchClassToName.result$
    else
        chord_name$ = "Silence"
    endif
    
    if show_all_detections
        if chord_name$ <> "Silence"
            appendInfoLine: fixed$(analysis_time, 3), "s: ", chord_name$
        endif
    endif
    
    # Chord change detection
    if chord_name$ <> previous_chord$
        if previous_chord$ <> ""
            chord_duration = analysis_time - current_chord_start
            if chord_duration >= min_chord_duration
                selectObject: textgrid
                
                if analysis_time < (duration - 0.001)
                    Insert boundary: 1, analysis_time
                endif
                
                interval_num = Get interval at time: 1, current_chord_start + 0.001
                Set interval text: 1, interval_num, current_chord$
                
                if not show_all_detections
                    appendInfoLine: "CHORD: ", fixed$(current_chord_start, 3), " - ", fixed$(analysis_time, 3), " s: ", current_chord$
                endif
                
                # Store for visualization
                if n_chord_history < max_history
                    n_chord_history += 1
                    chord_start_'n_chord_history' = current_chord_start
                    chord_end_'n_chord_history' = analysis_time
                    chord_label_'n_chord_history'$ = current_chord$
                endif
            endif
        endif
        
        current_chord$ = chord_name$
        current_chord_start = analysis_time
        previous_chord$ = chord_name$
    endif
    
    # Add notes to tier 2
    selectObject: textgrid
    next_boundary_time = analysis_time + time_step
    if next_boundary_time < (duration - 0.001)
        Insert boundary: 2, next_boundary_time
    endif
    interval_num = Get interval at time: 2, analysis_time + (time_step / 2)
    if notes_list$ <> ""
        Set interval text: 2, interval_num, notes_list$
    endif
    
    selectObject: extract, spectrum
    Remove
    
    analysis_time += time_step
endwhile

# Close final chord
if current_chord$ <> ""
    selectObject: textgrid
    n_intervals = Get number of intervals: 1
    Set interval text: 1, n_intervals, current_chord$
    if not show_all_detections
        appendInfoLine: "CHORD: ", fixed$(current_chord_start, 3), " - ", fixed$(duration, 3), " s: ", current_chord$
    endif
    
    if n_chord_history < max_history
        n_chord_history += 1
        chord_start_'n_chord_history' = current_chord_start
        chord_end_'n_chord_history' = duration
        chord_label_'n_chord_history'$ = current_chord$
    endif
endif

appendInfoLine: ""
appendInfoLine: "=== ANALYSIS COMPLETE ==="
appendInfoLine: "Analyzed ", frame_number, " frames"

selectObject: textgrid
n_chord_intervals = Get number of intervals: 1
appendInfoLine: "Detected ", n_chord_intervals, " chord segments"

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0, 0.6
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Chord Detection: " + sound_name$ + " (" + presetName$ + ")"
    
    # Waveform
    Select outer viewport: 0, 8, 0.8, 2.5
    Select inner viewport: 0.6, 7.6, 1.0, 2.3
    selectObject: sound
    Colour: "{0.4, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Waveform"
    
    # Chord timeline
    Select outer viewport: 0, 8, 2.7, 4.2
    Select inner viewport: 0.6, 7.6, 2.9, 4.0
    
    Axes: 0, duration, 0, 1
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration, 0, 1
    
    # Draw chord blocks
    for i from 1 to n_chord_history
        start_t = chord_start_'i'
        end_t = chord_end_'i'
        label$ = chord_label_'i'$
        
        # Color by chord type
        if index(label$, "Major") > 0
            col$ = "{0.4, 0.7, 0.4}"
        elsif index(label$, "Minor") > 0
            col$ = "{0.5, 0.5, 0.8}"
        elsif index(label$, "Diminished") > 0
            col$ = "{0.7, 0.4, 0.4}"
        elsif index(label$, "7th") > 0 or index(label$, "7") > 0
            col$ = "{0.7, 0.6, 0.3}"
        elsif index(label$, "Sus") > 0
            col$ = "{0.6, 0.7, 0.7}"
        else
            col$ = "{0.6, 0.6, 0.6}"
        endif
        
        Paint rectangle: col$, start_t, end_t, 0.1, 0.9
        
        # Label (if wide enough)
        mid_t = (start_t + end_t) / 2
        width = end_t - start_t
        if width > duration / 15
            Colour: "Black"
            Font size: 7
            Text: mid_t, "centre", 0.5, "half", label$
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Chords"
    Text bottom: "yes", "Time (s)"
    
    # Legend
    Select outer viewport: 0, 8, 4.4, 5.0
    Font size: 7
    Colour: "{0.4, 0.7, 0.4}"
    Text: 0.1, "left", 0.7, "half", "Major"
    Colour: "{0.5, 0.5, 0.8}"
    Text: 0.2, "left", 0.7, "half", "Minor"
    Colour: "{0.7, 0.6, 0.3}"
    Text: 0.3, "left", 0.7, "half", "7th"
    Colour: "{0.7, 0.4, 0.4}"
    Text: 0.4, "left", 0.7, "half", "Dim"
    Colour: "{0.6, 0.7, 0.7}"
    Text: 0.5, "left", 0.7, "half", "Sus"
    
    Font size: 10
    Colour: "Black"
endif

# Open TextGrid editor
selectObject: textgrid
plusObject: sound
View & Edit

selectObject: sound

# ============================================================
# PROCEDURES
# ============================================================

procedure pitchClassToName: .pitch_class
    if .pitch_class = 0
        .result$ = "C"
    elsif .pitch_class = 1
        .result$ = "C#"
    elsif .pitch_class = 2
        .result$ = "D"
    elsif .pitch_class = 3
        .result$ = "D#"
    elsif .pitch_class = 4
        .result$ = "E"
    elsif .pitch_class = 5
        .result$ = "F"
    elsif .pitch_class = 6
        .result$ = "F#"
    elsif .pitch_class = 7
        .result$ = "G"
    elsif .pitch_class = 8
        .result$ = "G#"
    elsif .pitch_class = 9
        .result$ = "A"
    elsif .pitch_class = 10
        .result$ = "A#"
    elsif .pitch_class = 11
        .result$ = "B"
    else
        .result$ = "?"
    endif
endproc

procedure createPitchClassSet: .n_notes
    .n = 0
    for .i from 1 to .n_notes
        .pc = note_pitch_class_'.i'
        .already_exists = 0
        for .j from 1 to .n
            .existing_pc = pitchClassSet_class_'.j'
            if .pc = .existing_pc
                .already_exists = 1
            endif
        endfor
        if not .already_exists
            .n += 1
            pitchClassSet_class_'.n' = .pc
        endif
    endfor
    
    # Sort the pitch class set (bubble sort)
    for .i from 1 to .n - 1
        for .j from 1 to .n - .i
            .j_plus_1 = .j + 1
            .val_j = pitchClassSet_class_'.j'
            .val_j_plus_1 = pitchClassSet_class_'.j_plus_1'
            
            if .val_j > .val_j_plus_1
                temp_val = .val_j
                pitchClassSet_class_'.j' = .val_j_plus_1
                pitchClassSet_class_'.j_plus_1' = temp_val
            endif
        endfor
    endfor
    
    createPitchClassSet.n = .n
    if .n > 0
        createPitchClassSet.root = pitchClassSet_class_1
    else
        createPitchClassSet.root = 0
    endif
endproc

procedure matchChord: .n_classes
    .result$ = "Unknown"
    
    # Try all possible roots
    for .try_root from 0 to 11
        # Calculate intervals from this root
        for .i from 1 to .n_classes
            .pc_val = pitchClassSet_class_'.i'
            .interval_'.i' = (.pc_val - .try_root + 12) mod 12
        endfor
        
        # Sort intervals
        for .i from 1 to .n_classes - 1
            for .j from 1 to .n_classes - .i
                .j_plus_1 = .j + 1
                .val_j = .interval_'.j'
                .val_j_plus_1 = .interval_'.j_plus_1'
                
                if .val_j > .val_j_plus_1
                    temp_interval = .val_j
                    .interval_'.j' = .val_j_plus_1
                    .interval_'.j_plus_1' = temp_interval
                endif
            endfor
        endfor
        
        # Build pattern string
        .pattern$ = ""
        for .i from 1 to .n_classes
            if .i > 1
                .pattern$ = .pattern$ + ","
            endif
            .pattern$ = .pattern$ + string$(.interval_'.i')
        endfor
        
        # CHORD DICTIONARY
        # 2-note (dyads)
        if .pattern$ = "0,7"
            @pitchClassToName: .try_root
            .result$ = pitchClassToName.result$ + "5"
        elsif .pattern$ = "0,5"
            @pitchClassToName: .try_root
            .result$ = pitchClassToName.result$ + "4"
        elsif .pattern$ = "0,3"
            @pitchClassToName: .try_root
            .result$ = pitchClassToName.result$ + " min3"
        elsif .pattern$ = "0,4"
            @pitchClassToName: .try_root
            .result$ = pitchClassToName.result$ + " maj3"
        
        # 3-note triads
        elsif .pattern$ = "0,4,7"
            @pitchClassToName: .try_root
            .result$ = pitchClassToName.result$ + " Major"
        elsif .pattern$ = "0,3,7"
            @pitchClassToName: .try_root
            .result$ = pitchClassToName.result$ + " Minor"
        elsif .pattern$ = "0,3,6"
            @pitchClassToName: .try_root
            .result$ = pitchClassToName.result$ + " Diminished"
        elsif .pattern$ = "0,4,8"
            @pitchClassToName: .try_root
            .result$ = pitchClassToName.result$ + " Augmented"
        elsif .pattern$ = "0,5,7"
            @pitchClassToName: .try_root
            .result$ = pitchClassToName.result$ + " Sus4"
        elsif .pattern$ = "0,2,7"
            @pitchClassToName: .try_root
            .result$ = pitchClassToName.result$ + " Sus2"
        
        # 4-note 7th chords
        elsif .pattern$ = "0,4,7,10"
            @pitchClassToName: .try_root
            .result$ = pitchClassToName.result$ + " Dom7"
        elsif .pattern$ = "0,4,7,11"
            @pitchClassToName: .try_root
            .result$ = pitchClassToName.result$ + " Maj7"
        elsif .pattern$ = "0,3,7,10"
            @pitchClassToName: .try_root
            .result$ = pitchClassToName.result$ + " Min7"
        elsif .pattern$ = "0,3,6,10"
            @pitchClassToName: .try_root
            .result$ = pitchClassToName.result$ + " m7b5"
        elsif .pattern$ = "0,3,6,9"
            @pitchClassToName: .try_root
            .result$ = pitchClassToName.result$ + " Dim7"
        elsif .pattern$ = "0,4,8,10"
            @pitchClassToName: .try_root
            .result$ = pitchClassToName.result$ + " Aug7"
        elsif .pattern$ = "0,3,7,11"
            @pitchClassToName: .try_root
            .result$ = pitchClassToName.result$ + " mMaj7"
        
        # 9th chords
        elsif .pattern$ = "0,2,4,7,10"
            @pitchClassToName: .try_root
            .result$ = pitchClassToName.result$ + "9"
        elsif .pattern$ = "0,2,4,7,11"
            @pitchClassToName: .try_root
            .result$ = pitchClassToName.result$ + " Maj9"
        elsif .pattern$ = "0,2,3,7,10"
            @pitchClassToName: .try_root
            .result$ = pitchClassToName.result$ + " Min9"
        
        # 6th chords
        elsif .pattern$ = "0,4,7,9"
            @pitchClassToName: .try_root
            .result$ = pitchClassToName.result$ + "6"
        elsif .pattern$ = "0,3,7,9"
            @pitchClassToName: .try_root
            .result$ = pitchClassToName.result$ + " m6"
        
        # Sus7
        elsif .pattern$ = "0,5,7,10"
            @pitchClassToName: .try_root
            .result$ = pitchClassToName.result$ + " 7sus4"
        elsif .pattern$ = "0,2,7,10"
            @pitchClassToName: .try_root
            .result$ = pitchClassToName.result$ + " 7sus2"
        
        # Add chords
        elsif .pattern$ = "0,2,4,7"
            @pitchClassToName: .try_root
            .result$ = pitchClassToName.result$ + " add9"
        elsif .pattern$ = "0,2,3,7"
            @pitchClassToName: .try_root
            .result$ = pitchClassToName.result$ + " m(add9)"
        elsif .pattern$ = "0,4,5,7"
            @pitchClassToName: .try_root
            .result$ = pitchClassToName.result$ + " add11"
        
        endif
        
        # Stop if found
        if .result$ <> "Unknown"
            .try_root = 12
        endif
    endfor
    
    # If no match, list notes
    if .result$ = "Unknown"
        .result$ = ""
        for .i from 1 to .n_classes
            .pc_val = pitchClassSet_class_'.i'
            @pitchClassToName: .pc_val
            if .i > 1
                .result$ = .result$ + "+"
            endif
            .result$ = .result$ + pitchClassToName.result$
        endfor
    endif
endproc