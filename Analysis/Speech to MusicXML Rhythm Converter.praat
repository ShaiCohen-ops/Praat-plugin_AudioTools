# ============================================================
# Praat AudioTools - Speech to MusicXML Rhythm Extractor.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Speech to MusicXML Rhythm Extractor
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================
# Speech to MusicXML Rhythm Extractor
# Works on selected Sound in Praat
# Outputs: MusicXML to Info window

clearinfo

# ===== USER FORM =====
form Speech to MusicXML Rhythm
    comment Tempo and quantization
    positive Tempo 120
    positive Divisions 8
    comment Time signature
    positive Time_signature_beats 4
    positive Time_signature_type 4
    comment Intensity analysis
    positive Intensity_step 0.015
    comment Peak detection
    positive Min_separation 0.10
    positive Prominence_dB 3.0
    comment Silence detection
    positive Min_silent_duration 0.12
    positive Min_sounding_duration 0.09
    integer Silence_threshold -25
endform

# ===== PARAMETERS =====
tempo = tempo
divisions = divisions
time_sig_beats = time_signature_beats
time_sig_type = time_signature_type
intensity_step = intensity_step
min_separation = min_separation
prominence_db = prominence_dB
min_silent_dur = min_silent_duration
min_sounding_dur = min_sounding_duration
silence_threshold = silence_threshold

# ===== GET SELECTED SOUND =====
sound = selected("Sound")
sound_name$ = selected$("Sound")
selectObject: sound
duration = Get total duration
sample_rate = Get sampling frequency

# ===== CREATE INTENSITY =====
selectObject: sound
intensity = To Intensity: 100, intensity_step, "yes"

# ===== DETECT SILENCE/SPEECH INTERVALS =====
selectObject: sound
textgrid = To TextGrid (silences): 100, 0, silence_threshold, min_silent_dur, min_sounding_dur, "silent", "sounding"

# ===== FIND ONSETS =====
n_intervals = Get number of intervals: 1
onset_count = 0

# Pre-allocate array space
for i from 1 to 1000
    onset_time[i] = 0
endfor

selectObject: intensity

# Process each sounding interval
for i from 1 to n_intervals
    selectObject: textgrid
    label$ = Get label of interval: 1, i
    
    if label$ = "sounding"
        t_start = Get start time of interval: 1, i
        t_end = Get end time of interval: 1, i
        
        # Find peaks in this interval
        selectObject: intensity
        
        t = t_start + min_separation
        last_onset = t_start - min_separation
        
        while t < t_end
            int_val = Get value at time: t, "Linear"
            
            if int_val != undefined
                # Check if local maximum
                t_before = t - 0.01
                t_after = t + 0.01
                
                if t_before >= t_start and t_after <= t_end
                    int_before = Get value at time: t_before, "Linear"
                    int_after = Get value at time: t_after, "Linear"
                    
                    # Check minimum separation
                    if t - last_onset >= min_separation
                        # Check if it's a peak
                        if int_val > int_before and int_val > int_after
                            # Check prominence vs local median
                            t_med_start = max(t - 0.15, t_start)
                            t_med_end = min(t + 0.15, t_end)
                            
                            # Estimate local median (simple mean approximation)
                            local_sum = 0
                            local_count = 0
                            t_local = t_med_start
                            while t_local <= t_med_end
                                local_val = Get value at time: t_local, "Linear"
                                if local_val != undefined
                                    local_sum = local_sum + local_val
                                    local_count = local_count + 1
                                endif
                                t_local = t_local + 0.02
                            endwhile
                            
                            if local_count > 0
                                local_median = local_sum / local_count
                                
                                # Check prominence
                                if int_val - local_median >= prominence_db
                                    onset_count = onset_count + 1
                                    onset_time[onset_count] = t
                                    last_onset = t
                                    t = t + min_separation
                                endif
                            endif
                        endif
                    endif
                endif
            endif
            
            t = t + 0.005
        endwhile
    endif
endfor

# ===== QUANTIZE & BUILD MUSICXML =====
if onset_count = 0
    writeInfoLine: "No onsets detected!"
    exitScript()
endif

# Beat grid setup
beat_dur = 60.0 / tempo
division_dur = beat_dur / (divisions / time_sig_type)
measure_dur = beat_dur * time_sig_beats

# Start building XML
xml$ = "<?xml version=""1.0"" encoding=""UTF-8""?>" + newline$
xml$ = xml$ + "<!DOCTYPE score-partwise PUBLIC ""-//Recordare//DTD MusicXML 3.1 Partwise//EN"" ""http://www.musicxml.org/dtds/partwise.dtd"">" + newline$
xml$ = xml$ + "<score-partwise version=""3.1"">" + newline$
xml$ = xml$ + "  <part-list>" + newline$
xml$ = xml$ + "    <score-part id=""P1"">" + newline$
xml$ = xml$ + "      <part-name>Speech Rhythm</part-name>" + newline$
xml$ = xml$ + "    </score-part>" + newline$
xml$ = xml$ + "  </part-list>" + newline$
xml$ = xml$ + "  <part id=""P1"">" + newline$

# Quantize and emit notes
measure_num = 1
measure_time = 0

xml$ = xml$ + "    <measure number=""1"">" + newline$
xml$ = xml$ + "      <attributes>" + newline$
xml$ = xml$ + "        <divisions>" + string$(divisions) + "</divisions>" + newline$
xml$ = xml$ + "        <time>" + newline$
xml$ = xml$ + "          <beats>" + string$(time_sig_beats) + "</beats>" + newline$
xml$ = xml$ + "          <beat-type>" + string$(time_sig_type) + "</beat-type>" + newline$
xml$ = xml$ + "        </time>" + newline$
xml$ = xml$ + "        <clef><sign>G</sign><line>2</line></clef>" + newline$
xml$ = xml$ + "      </attributes>" + newline$

current_time = 0

for i from 1 to onset_count
    onset = onset_time[i]
    
    # Calculate duration until this onset
    dur_seconds = onset - current_time
    dur_divs = round(dur_seconds / division_dur)
    
    if dur_divs > 0
        # Emit rest before onset
        call emitNote "rest" dur_divs
    endif
    
    # Calculate note duration
    if i < onset_count
        note_dur = onset_time[i + 1] - onset
    else
        note_dur = duration - onset
    endif
    
    note_dur_divs = round(note_dur / division_dur)
    if note_dur_divs < 1
        note_dur_divs = 1
    endif
    
    # Emit note
    call emitNote "note" note_dur_divs
    
    current_time = onset + note_dur
endfor

# Close final measure
xml$ = xml$ + "    </measure>" + newline$
xml$ = xml$ + "  </part>" + newline$
xml$ = xml$ + "</score-partwise>"

# ===== CLEANUP =====
removeObject: intensity, textgrid

# Output everything
appendInfoLine: xml$

# ===== PROCEDURES =====
procedure emitNote note_or_rest$ dur_divs
    while dur_divs > 0
        # Remaining room in this measure (in divisions)
        # Calculate based on time signature
        measure_capacity = time_sig_beats * (divisions / time_sig_type) * time_sig_type
        measure_remaining = measure_capacity - measure_time
        
        if measure_remaining <= 0
            xml$ = xml$ + "    </measure>" + newline$
            measure_num = measure_num + 1
            measure_time = 0
            measure_str$ = string$(measure_num)
            xml$ = xml$ + "    <measure number=""" + measure_str$ + """>" + newline$
            measure_remaining = measure_capacity
        endif

        # Limit to what fits this measure
        max_chunk = min(dur_divs, measure_remaining)

        # Choose the largest canonical chunk that fits
        if max_chunk >= 32
            note_type$ = "whole"
            write_dur = 32
        elsif max_chunk >= 16
            note_type$ = "half"
            write_dur = 16
        elsif max_chunk >= 8
            note_type$ = "quarter"
            write_dur = 8
        elsif max_chunk >= 4
            note_type$ = "eighth"
            write_dur = 4
        elsif max_chunk >= 2
            note_type$ = "16th"
            write_dur = 2
        else
            note_type$ = "16th"
            write_dur = 1
        endif

        dur_str$ = string$(write_dur)
        
        xml$ = xml$ + "      <note>" + newline$
        if note_or_rest$ = "rest"
            xml$ = xml$ + "        <rest/>" + newline$
        else
            xml$ = xml$ + "        <pitch><step>C</step><octave>4</octave></pitch>" + newline$
        endif
        xml$ = xml$ + "        <duration>" + dur_str$ + "</duration>" + newline$
        xml$ = xml$ + "        <type>" + note_type$ + "</type>" + newline$
        xml$ = xml$ + "      </note>" + newline$

        measure_time = measure_time + write_dur
        dur_divs = dur_divs - write_dur
    endwhile
endproc