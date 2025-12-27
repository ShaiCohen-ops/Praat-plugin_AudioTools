# ============================================================
# Praat AudioTools - Speech to MusicXML Rhythm Extractor v2.7
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.7 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Advanced Speech to MusicXML Rhythm Extractor with:
#   - Automatic tempo estimation from inter-onset intervals
#   - Multi-feature onset detection (intensity + spectral flux)
#   - Adaptive peak detection with parabolic interpolation
#   - Parametric note duration mapping
#   - Dotted note support
#   - Dynamics extraction from intensity contour
#   - Compound meter support
#   - TextGrid output with rhythm annotations
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#   Open the MusicXML output in notation software (MuseScore, Finale, etc.)
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit 
#   for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

clearinfo

# ===== USER FORM =====
form Speech to MusicXML Rhythm v2.7
    comment === Tempo and Quantization ===
    boolean Auto_detect_tempo 1
    positive Manual_tempo_(BPM) 120
    optionmenu Pulse_unit: 3
        option Whole note
        option Half note
        option Quarter note
        option Eighth note
        option 16th note
    positive Divisions_per_quarter 8
    boolean Allow_dotted_notes 1
    
    comment === Time Signature ===
    boolean Auto_detect_meter 1
    positive Time_signature_beats 4
    positive Time_signature_type 4
    boolean Compound_meter 0
    
    comment === Onset Detection ===
    optionmenu Detection_method: 1
        option Intensity only
        option Multi-feature (intensity + spectral)
        option Syllable nuclei
    positive Min_onset_separation_(s) 0.08
    positive Prominence_threshold_(dB) 2.5
    
    comment === Silence Detection ===
    positive Min_silent_duration_(s) 0.10
    positive Min_sounding_duration_(s) 0.08
    integer Silence_threshold_(dB) -25
    
    comment === Dynamics ===
    boolean Extract_dynamics 1
    positive Dynamics_smoothing_(s) 0.1
    
    comment === Output ===
    optionmenu Output_pitch: 1
        option C4 (middle C)
        option B3 (unpitched percussion)
        option E4 (speech line)
    boolean Include_comments 1
    boolean Create_TextGrid 1
endform

# ===== COPY PARAMETERS =====
auto_tempo = auto_detect_tempo
manual_tempo = manual_tempo
pulse_unit = pulse_unit
divisions = divisions_per_quarter
allow_dotted = allow_dotted_notes
auto_meter = auto_detect_meter
time_sig_beats = time_signature_beats
time_sig_type = time_signature_type
compound_meter = compound_meter
detection_method = detection_method
min_separation = min_onset_separation
prominence_threshold = prominence_threshold
min_silent_dur = min_silent_duration
min_sounding_dur = min_sounding_duration
silence_threshold = silence_threshold
extract_dynamics = extract_dynamics
dynamics_smoothing = dynamics_smoothing
output_pitch = output_pitch
include_comments = include_comments
create_textgrid_output = create_TextGrid

# ===== PITCH SETTINGS =====
if output_pitch = 1
    pitch_step$ = "C"
    pitch_octave = 4
elsif output_pitch = 2
    pitch_step$ = "B"
    pitch_octave = 3
else
    pitch_step$ = "E"
    pitch_octave = 4
endif

# ===== GET SELECTED SOUND =====
if numberOfSelected("Sound") = 0
    exitScript: "Please select a Sound object first."
endif
sound = selected("Sound")
sound_name$ = selected$("Sound")
selectObject: sound
duration = Get total duration
sample_rate = Get sampling frequency

# ===== CREATE ANALYSIS OBJECTS =====
selectObject: sound
intensity = To Intensity: 100, 0.01, "yes"
intensity_min = Get minimum: 0, 0, "Parabolic"
intensity_max = Get maximum: 0, 0, "Parabolic"

# Smoothed intensity for dynamics
selectObject: sound
intensity_smooth = To Intensity: 100, dynamics_smoothing, "yes"

# ===== DETECT SILENCE/SPEECH INTERVALS =====
selectObject: sound
textgrid = To TextGrid (silences): 100, 0, silence_threshold, min_silent_dur, min_sounding_dur, "silent", "sounding"

# ===== SPECTRAL FLUX (for multi-feature detection) =====
if detection_method = 2
    selectObject: sound
    spectrogram = To Spectrogram: 0.015, 5000, 0.005, 20, "Gaussian"
endif

# ===== ONSET DETECTION =====
max_onsets = 2000
for i from 1 to max_onsets
    onset_time[i] = 0
    onset_intensity[i] = 0
endfor

onset_count = 0

selectObject: textgrid
n_intervals = Get number of intervals: 1

# ----- METHOD 1 & 2: Intensity-based with improved peak detection -----
if detection_method = 1 or detection_method = 2
    
    for interval_i from 1 to n_intervals
        selectObject: textgrid
        label$ = Get label of interval: 1, interval_i
        
        if label$ = "sounding"
            t_start = Get start time of interval: 1, interval_i
            t_end = Get end time of interval: 1, interval_i
            interval_dur = t_end - t_start
            
            adaptive_window = max(0.02, min(0.05, interval_dur / 10))
            
            selectObject: intensity
            
            t = t_start + adaptive_window
            last_onset = t_start - min_separation
            
            while t < t_end - adaptive_window
                int_val = Get value at time: t, "Cubic"
                
                if int_val <> undefined
                    t_m1 = t - adaptive_window/2
                    t_p1 = t + adaptive_window/2
                    
                    int_m1 = Get value at time: t_m1, "Cubic"
                    int_p1 = Get value at time: t_p1, "Cubic"
                    
                    if int_m1 <> undefined and int_p1 <> undefined
                        
                        is_peak = (int_val > int_m1) and (int_val > int_p1)
                        
                        if is_peak and (t - last_onset >= min_separation)
                            
                            alpha = int_m1
                            beta = int_val
                            gamma = int_p1
                            
                            if (alpha - 2*beta + gamma) <> 0
                                p = 0.5 * (alpha - gamma) / (alpha - 2*beta + gamma)
                                refined_t = t + p * (adaptive_window/2)
                                refined_int = beta - 0.25 * (alpha - gamma) * p
                            else
                                refined_t = t
                                refined_int = int_val
                            endif
                            
                            window_start = max(t - 0.15, t_start)
                            window_end = min(t + 0.15, t_end)
                            
                            n_samples = 15
                            sample_step = (window_end - window_start) / n_samples
                            
                            for s from 1 to n_samples
                                sample_t = window_start + (s - 0.5) * sample_step
                                sample_vals[s] = Get value at time: sample_t, "Cubic"
                                if sample_vals[s] = undefined
                                    sample_vals[s] = int_val
                                endif
                            endfor
                            
                            # Simple bubble sort for median
                            for s1 from 1 to n_samples - 1
                                for s2 from s1 + 1 to n_samples
                                    if sample_vals[s1] > sample_vals[s2]
                                        temp_val = sample_vals[s1]
                                        sample_vals[s1] = sample_vals[s2]
                                        sample_vals[s2] = temp_val
                                    endif
                                endfor
                            endfor
                            
                            local_median = sample_vals[ceiling(n_samples / 2)]
                            prominence = refined_int - local_median
                            
                            spectral_onset = 1
                            
                            if detection_method = 2
                                selectObject: spectrogram
                                
                                slice_before = Get power at: refined_t - 0.02, 1000
                                slice_after = Get power at: refined_t + 0.01, 1000
                                
                                if slice_before <> undefined and slice_after <> undefined
                                    flux = slice_after - slice_before
                                    spectral_onset = (flux > 0)
                                endif
                                
                                selectObject: intensity
                            endif
                            
                            if prominence >= prominence_threshold and spectral_onset
                                onset_count = onset_count + 1
                                if onset_count <= max_onsets
                                    onset_time[onset_count] = refined_t
                                    onset_intensity[onset_count] = refined_int
                                    last_onset = refined_t
                                endif
                            endif
                        endif
                    endif
                endif
                
                t = t + 0.005
            endwhile
        endif
    endfor

# ----- METHOD 3: Syllable nuclei -----
elsif detection_method = 3
    
    selectObject: sound
    pitch_obj = To Pitch: 0, 75, 600
    
    for interval_i from 1 to n_intervals
        selectObject: textgrid
        label$ = Get label of interval: 1, interval_i
        
        if label$ = "sounding"
            t_start = Get start time of interval: 1, interval_i
            t_end = Get end time of interval: 1, interval_i
            
            selectObject: intensity
            
            t = t_start + 0.03
            last_onset = t_start - min_separation
            
            while t < t_end - 0.03
                local_max_t = Get time of maximum: t - 0.04, t + 0.04, "Parabolic"
                local_max_int = Get maximum: t - 0.04, t + 0.04, "Parabolic"
                
                if local_max_t <> undefined and local_max_int <> undefined
                    if abs(local_max_t - t) < 0.01 and (local_max_t - last_onset >= min_separation)
                        
                        selectObject: pitch_obj
                        f0 = Get value at time: local_max_t, "Hertz", "Linear"
                        
                        selectObject: intensity
                        
                        if f0 <> undefined
                            onset_count = onset_count + 1
                            if onset_count <= max_onsets
                                onset_time[onset_count] = local_max_t
                                onset_intensity[onset_count] = local_max_int
                                last_onset = local_max_t
                            endif
                        endif
                    endif
                endif
                
                t = t + 0.02
            endwhile
        endif
    endfor
    
    removeObject: pitch_obj
endif

# ===== VALIDATE ONSETS =====
if onset_count < 2
    writeInfoLine: "Not enough onsets detected (need at least 2)!"
    appendInfoLine: "Try adjusting detection parameters."
    
    removeObject: intensity, intensity_smooth, textgrid
    if detection_method = 2
        removeObject: spectrogram
    endif
    
    exitScript()
endif

# =====================================================================
# TEMPO ESTIMATION
# =====================================================================

if auto_tempo
    @estimateTempo
    tempo = estimateTempo.tempo
    tempo_confidence = estimateTempo.confidence
    dominant_ioi = estimateTempo.dominant_ioi
    pulse_name$ = estimateTempo.pulse_name$
else
    tempo = manual_tempo
    tempo_confidence = 1.0
    dominant_ioi = 0
    pulse_name$ = "manual"
endif

# =====================================================================
# METER ESTIMATION
# =====================================================================

if auto_meter
    @estimateMeter
    time_sig_beats = estimateMeter.beats
    time_sig_type = estimateMeter.beat_type
    compound_meter = estimateMeter.compound
endif

# ===== CALCULATE RHYTHMIC GRID =====
beat_dur = 60.0 / tempo
quarter_dur = beat_dur

divs_per_whole = divisions * 4
divs_per_half = divisions * 2
divs_per_quarter = divisions
divs_per_eighth = max(1, divisions / 2)
divs_per_16th = max(1, divisions / 4)
divs_per_32nd = max(1, divisions / 8)

division_dur = quarter_dur / divisions

if compound_meter
    measure_dur = (time_sig_beats / 3) * (beat_dur * 1.5)
    divs_per_measure = time_sig_beats * (divisions / 2)
else
    measure_dur = beat_dur * time_sig_beats
    divs_per_measure = time_sig_beats * divisions
endif

# ===== QUANTIZE ONSETS =====
for i from 1 to onset_count
    raw_divs = onset_time[i] / division_dur
    quantized_divs[i] = round(raw_divs)
    quantization_error[i] = abs(raw_divs - quantized_divs[i]) * division_dur
endfor

# ===== BUILD NOTE LIST =====
max_notes = 3000
for i from 1 to max_notes
    note_type[i] = 0
    note_duration[i] = 0
    note_dotted[i] = 0
    note_time[i] = 0
    note_dynamics[i] = 0
    note_value_type$[i] = ""
endfor

note_list_count = 0
current_div = 0

for i from 1 to onset_count
    target_div = quantized_divs[i]
    
    # Rest before this onset
    rest_dur = target_div - current_div
    
    if rest_dur > 0
        @addToNoteList: 0, rest_dur, current_div * division_dur, 0
    endif
    
    # Note duration
    if i < onset_count
        next_div = quantized_divs[i + 1]
        note_dur = next_div - target_div
    else
        end_div = round(duration / division_dur)
        note_dur = end_div - target_div
        if note_dur < 1
            note_dur = divs_per_eighth
        endif
    endif
    
    if note_dur < 1
        note_dur = 1
    endif
    
    # Get dynamics
    if extract_dynamics
        selectObject: intensity_smooth
        note_int = Get value at time: onset_time[i], "Cubic"
        if note_int = undefined
            note_int = (intensity_min + intensity_max) / 2
        endif
        dyn_norm = (note_int - intensity_min) / (intensity_max - intensity_min + 0.001)
    else
        dyn_norm = 0.5
    endif
    
    @addToNoteList: 1, note_dur, onset_time[i], dyn_norm
    
    current_div = target_div + note_dur
endfor

# ===== BUILD MUSICXML =====
xml$ = "<?xml version=""1.0"" encoding=""UTF-8""?>" + newline$
xml$ = xml$ + "<!DOCTYPE score-partwise PUBLIC ""-//Recordare//DTD MusicXML 3.1 Partwise//EN"" ""http://www.musicxml.org/dtds/partwise.dtd"">" + newline$
xml$ = xml$ + "<score-partwise version=""3.1"">" + newline$

if include_comments
    xml$ = xml$ + "  <!-- Generated by Praat AudioTools v2.7 -->" + newline$
    xml$ = xml$ + "  <!-- Source: " + sound_name$ + " -->" + newline$
    if auto_tempo
        xml$ = xml$ + "  <!-- Auto-detected tempo: " + string$(tempo) + " BPM (confidence: " + fixed$(tempo_confidence * 100, 0) + "%) -->" + newline$
    endif
    xml$ = xml$ + "  <!-- Onsets detected: " + string$(onset_count) + " -->" + newline$
endif

xml$ = xml$ + "  <work>" + newline$
xml$ = xml$ + "    <work-title>" + sound_name$ + " - Rhythm</work-title>" + newline$
xml$ = xml$ + "  </work>" + newline$

xml$ = xml$ + "  <identification>" + newline$
xml$ = xml$ + "    <creator type=""composer"">Speech Analysis</creator>" + newline$
xml$ = xml$ + "    <encoding>" + newline$
xml$ = xml$ + "      <software>Praat AudioTools v2.7</software>" + newline$
xml$ = xml$ + "    </encoding>" + newline$
xml$ = xml$ + "  </identification>" + newline$

xml$ = xml$ + "  <part-list>" + newline$
xml$ = xml$ + "    <score-part id=""P1"">" + newline$
xml$ = xml$ + "      <part-name>Speech Rhythm</part-name>" + newline$
xml$ = xml$ + "    </score-part>" + newline$
xml$ = xml$ + "  </part-list>" + newline$
xml$ = xml$ + "  <part id=""P1"">" + newline$

measure_num = 1
measure_position = 0

xml$ = xml$ + "    <measure number=""1"">" + newline$
xml$ = xml$ + "      <attributes>" + newline$
xml$ = xml$ + "        <divisions>" + string$(divisions) + "</divisions>" + newline$
xml$ = xml$ + "        <time>" + newline$
xml$ = xml$ + "          <beats>" + string$(time_sig_beats) + "</beats>" + newline$
xml$ = xml$ + "          <beat-type>" + string$(time_sig_type) + "</beat-type>" + newline$
xml$ = xml$ + "        </time>" + newline$
xml$ = xml$ + "        <clef>" + newline$
xml$ = xml$ + "          <sign>G</sign>" + newline$
xml$ = xml$ + "          <line>2</line>" + newline$
xml$ = xml$ + "        </clef>" + newline$
xml$ = xml$ + "      </attributes>" + newline$

xml$ = xml$ + "      <direction placement=""above"">" + newline$
xml$ = xml$ + "        <direction-type>" + newline$
xml$ = xml$ + "          <metronome>" + newline$
xml$ = xml$ + "            <beat-unit>quarter</beat-unit>" + newline$
xml$ = xml$ + "            <per-minute>" + string$(tempo) + "</per-minute>" + newline$
xml$ = xml$ + "          </metronome>" + newline$
xml$ = xml$ + "        </direction-type>" + newline$
xml$ = xml$ + "      </direction>" + newline$

# Emit notes from note list
for n from 1 to note_list_count
    if note_type[n] = 0
        type$ = "rest"
    else
        type$ = "note"
    endif
    
    @emitXMLElement: type$, note_duration[n], note_dynamics[n]
endfor

# Fill final measure
final_measure_remaining = divs_per_measure - measure_position
if final_measure_remaining > 0 and final_measure_remaining < divs_per_measure
    @emitXMLElement: "rest", final_measure_remaining, 0
endif

xml$ = xml$ + "    </measure>" + newline$
xml$ = xml$ + "  </part>" + newline$
xml$ = xml$ + "</score-partwise>"

# ===== CREATE RHYTHM TEXTGRID =====
if create_textgrid_output
    @createRhythmTextGrid
endif

# ===== CLEANUP =====
removeObject: intensity, intensity_smooth, textgrid
if detection_method = 2
    removeObject: spectrogram
endif

# ===== OUTPUT =====
writeInfoLine: xml$

appendInfoLine: ""
appendInfoLine: "===== ANALYSIS SUMMARY ====="
appendInfoLine: "Source: " + sound_name$
appendInfoLine: "Duration: " + fixed$(duration, 3) + " s"
appendInfoLine: "Onsets detected: " + string$(onset_count)
appendInfoLine: "Notes/rests generated: " + string$(note_list_count)
appendInfoLine: ""
if auto_tempo
    appendInfoLine: "=== TEMPO ESTIMATION ==="
    appendInfoLine: "Detected tempo: " + string$(tempo) + " BPM"
    appendInfoLine: "Confidence: " + fixed$(tempo_confidence * 100, 1) + "%"
    appendInfoLine: "Dominant IOI: " + fixed$(dominant_ioi * 1000, 1) + " ms"
    appendInfoLine: "Pulse mapped to: " + pulse_name$
endif
appendInfoLine: ""
appendInfoLine: "Time signature: " + string$(time_sig_beats) + "/" + string$(time_sig_type)
if compound_meter
    appendInfoLine: "(Compound meter)"
endif
appendInfoLine: "Divisions per quarter: " + string$(divisions)

total_error = 0
max_error = 0
for i from 1 to onset_count
    total_error = total_error + quantization_error[i]
    if quantization_error[i] > max_error
        max_error = quantization_error[i]
    endif
endfor
avg_error = total_error / onset_count
appendInfoLine: ""
appendInfoLine: "=== QUANTIZATION QUALITY ==="
appendInfoLine: "Average error: " + fixed$(avg_error * 1000, 1) + " ms"
appendInfoLine: "Maximum error: " + fixed$(max_error * 1000, 1) + " ms"

if avg_error > 0.03
    appendInfoLine: ""
    appendInfoLine: "NOTE: High quantization error. Try different tempo or higher divisions."
endif

if create_textgrid_output
    appendInfoLine: ""
    appendInfoLine: "Rhythm TextGrid created: " + sound_name$ + "_rhythm"
endif

appendInfoLine: ""
appendInfoLine: "=== USAGE ==="
appendInfoLine: "Copy the MusicXML output above and save as .xml file,"
appendInfoLine: "then open in MuseScore, Finale, Sibelius, or other notation software."

# =====================================================================
# PROCEDURES
# =====================================================================

procedure addToNoteList: .is_note, .dur_divs, .time, .dynamics
    while .dur_divs > 0
        @getBestNoteValue: .dur_divs
        
        note_list_count = note_list_count + 1
        note_type[note_list_count] = .is_note
        note_duration[note_list_count] = getBestNoteValue.duration
        note_dotted[note_list_count] = getBestNoteValue.dotted
        note_time[note_list_count] = .time
        note_dynamics[note_list_count] = .dynamics
        note_value_type$[note_list_count] = getBestNoteValue.type$
        
        .dur_divs = .dur_divs - getBestNoteValue.duration
        .time = .time + getBestNoteValue.duration * division_dur
    endwhile
endproc

procedure estimateTempo
    n_iois = onset_count - 1
    
    for i from 1 to n_iois
        ioi[i] = onset_time[i + 1] - onset_time[i]
    endfor
    
    ioi_min = ioi[1]
    ioi_max = ioi[1]
    ioi_sum = 0
    
    for i from 1 to n_iois
        if ioi[i] < ioi_min
            ioi_min = ioi[i]
        endif
        if ioi[i] > ioi_max
            ioi_max = ioi[i]
        endif
        ioi_sum = ioi_sum + ioi[i]
    endfor
    
    ioi_mean = ioi_sum / n_iois
    
    hist_min = max(0.05, ioi_min * 0.8)
    hist_max = min(2.0, ioi_max * 1.2)
    n_bins = 50
    bin_width = (hist_max - hist_min) / n_bins
    
    for b from 1 to n_bins
        hist_count[b] = 0
        hist_center[b] = hist_min + (b - 0.5) * bin_width
    endfor
    
    for i from 1 to n_iois
        if ioi[i] >= hist_min and ioi[i] < hist_max
            bin_idx = floor((ioi[i] - hist_min) / bin_width) + 1
            if bin_idx >= 1 and bin_idx <= n_bins
                hist_count[bin_idx] = hist_count[bin_idx] + 1
            endif
        endif
    endfor
    
    peak_bin = 1
    peak_count = hist_count[1]
    
    for b from 2 to n_bins
        if hist_count[b] > peak_count
            peak_count = hist_count[b]
            peak_bin = b
        endif
    endfor
    
    .dominant_ioi = hist_center[peak_bin]
    
    weight_sum = 0
    weighted_ioi = 0
    
    for b from max(1, peak_bin - 2) to min(n_bins, peak_bin + 2)
        weight_sum = weight_sum + hist_count[b]
        weighted_ioi = weighted_ioi + hist_count[b] * hist_center[b]
    endfor
    
    if weight_sum > 0
        .dominant_ioi = weighted_ioi / weight_sum
    endif
    
    total_count = 0
    for b from 1 to n_bins
        total_count = total_count + hist_count[b]
    endfor
    
    peak_region_count = 0
    for b from max(1, peak_bin - 2) to min(n_bins, peak_bin + 2)
        peak_region_count = peak_region_count + hist_count[b]
    endfor
    
    .confidence = peak_region_count / (total_count + 0.001)
    
    if pulse_unit = 1
        quarter_dur_est = .dominant_ioi / 4
        .pulse_name$ = "whole note"
    elsif pulse_unit = 2
        quarter_dur_est = .dominant_ioi / 2
        .pulse_name$ = "half note"
    elsif pulse_unit = 3
        quarter_dur_est = .dominant_ioi
        .pulse_name$ = "quarter note"
    elsif pulse_unit = 4
        quarter_dur_est = .dominant_ioi * 2
        .pulse_name$ = "eighth note"
    else
        quarter_dur_est = .dominant_ioi * 4
        .pulse_name$ = "16th note"
    endif
    
    raw_tempo = 60.0 / quarter_dur_est
    
    if raw_tempo < 40
        raw_tempo = raw_tempo * 2
    elsif raw_tempo > 240
        raw_tempo = raw_tempo / 2
    endif
    
    .tempo = round(raw_tempo)
    .tempo = max(30, min(300, .tempo))
endproc

procedure estimateMeter
    .beats = 4
    .beat_type = 4
    .compound = 0
    
    if onset_count >= 4
        int_sum = 0
        for i from 1 to onset_count
            int_sum = int_sum + onset_intensity[i]
        endfor
        int_mean = int_sum / onset_count
        
        accent_count = 0
        last_accent = 0
        
        for i from 1 to max_onsets
            accent_interval[i] = 0
        endfor
        
        for i from 1 to onset_count
            if onset_intensity[i] > int_mean * 1.1
                if last_accent > 0
                    accent_count = accent_count + 1
                    accent_interval[accent_count] = i - last_accent
                endif
                last_accent = i
            endif
        endfor
        
        if accent_count >= 3
            count_2 = 0
            count_3 = 0
            count_4 = 0
            count_6 = 0
            
            for i from 1 to accent_count
                if accent_interval[i] = 2
                    count_2 = count_2 + 1
                elsif accent_interval[i] = 3
                    count_3 = count_3 + 1
                elsif accent_interval[i] = 4
                    count_4 = count_4 + 1
                elsif accent_interval[i] = 6
                    count_6 = count_6 + 1
                endif
            endfor
            
            if count_6 > count_4 and count_6 > count_3 and count_6 > count_2
                .beats = 6
                .beat_type = 8
                .compound = 1
            elsif count_3 > count_4 and count_3 > count_2
                .beats = 3
                .beat_type = 4
            elsif count_2 > count_4
                .beats = 2
                .beat_type = 4
            endif
        endif
    endif
endproc

procedure emitXMLElement: .type$, .dur_divs, .dynamics
    while .dur_divs > 0
        if measure_position >= divs_per_measure
            xml$ = xml$ + "    </measure>" + newline$
            measure_num = measure_num + 1
            xml$ = xml$ + "    <measure number=""" + string$(measure_num) + """>" + newline$
            measure_position = 0
        endif
        
        room_in_measure = divs_per_measure - measure_position
        chunk_dur = min(.dur_divs, room_in_measure)
        
        @getBestNoteValue: chunk_dur
        write_dur = getBestNoteValue.duration
        local_note_type$ = getBestNoteValue.type$
        is_dotted = getBestNoteValue.dotted
        
        xml$ = xml$ + "      <note>" + newline$
        
        if .type$ = "rest"
            xml$ = xml$ + "        <rest/>" + newline$
        else
            xml$ = xml$ + "        <pitch>" + newline$
            xml$ = xml$ + "          <step>" + pitch_step$ + "</step>" + newline$
            xml$ = xml$ + "          <octave>" + string$(pitch_octave) + "</octave>" + newline$
            xml$ = xml$ + "        </pitch>" + newline$
        endif
        
        xml$ = xml$ + "        <duration>" + string$(write_dur) + "</duration>" + newline$
        xml$ = xml$ + "        <type>" + local_note_type$ + "</type>" + newline$
        
        if is_dotted
            xml$ = xml$ + "        <dot/>" + newline$
        endif
        
        if .type$ <> "rest" and extract_dynamics
            @getDynamicMarking: .dynamics
            if getDynamicMarking.marking$ <> ""
                xml$ = xml$ + "        <dynamics>" + newline$
                xml$ = xml$ + "          <" + getDynamicMarking.marking$ + "/>" + newline$
                xml$ = xml$ + "        </dynamics>" + newline$
            endif
        endif
        
        xml$ = xml$ + "      </note>" + newline$
        
        measure_position = measure_position + write_dur
        .dur_divs = .dur_divs - write_dur
    endwhile
endproc

procedure getBestNoteValue: .target_dur
    .dotted = 0
    
    .whole = divisions * 4
    .half = divisions * 2
    .quarter = divisions
    .eighth = max(1, divisions / 2)
    .sixteenth = max(1, divisions / 4)
    .thirtysecond = max(1, divisions / 8)
    
    .dotted_half = .half + .quarter
    .dotted_quarter = .quarter + .eighth
    .dotted_eighth = .eighth + .sixteenth
    
    if .target_dur >= .whole
        .duration = .whole
        .type$ = "whole"
    elsif .target_dur >= .dotted_half and allow_dotted
        .duration = .dotted_half
        .type$ = "half"
        .dotted = 1
    elsif .target_dur >= .half
        .duration = .half
        .type$ = "half"
    elsif .target_dur >= .dotted_quarter and allow_dotted
        .duration = .dotted_quarter
        .type$ = "quarter"
        .dotted = 1
    elsif .target_dur >= .quarter
        .duration = .quarter
        .type$ = "quarter"
    elsif .target_dur >= .dotted_eighth and allow_dotted
        .duration = .dotted_eighth
        .type$ = "eighth"
        .dotted = 1
    elsif .target_dur >= .eighth
        .duration = .eighth
        .type$ = "eighth"
    elsif .target_dur >= .sixteenth
        .duration = .sixteenth
        .type$ = "16th"
    elsif .target_dur >= .thirtysecond
        .duration = .thirtysecond
        .type$ = "32nd"
    else
        .duration = 1
        .type$ = "32nd"
    endif
    
    if .duration > .target_dur
        if .type$ = "whole"
            .duration = .half
            .type$ = "half"
            .dotted = 0
        elsif .type$ = "half" and .dotted = 1
            .duration = .half
            .dotted = 0
        elsif .type$ = "half"
            .duration = .quarter
            .type$ = "quarter"
        elsif .type$ = "quarter" and .dotted = 1
            .duration = .quarter
            .dotted = 0
        elsif .type$ = "quarter"
            .duration = .eighth
            .type$ = "eighth"
        elsif .type$ = "eighth" and .dotted = 1
            .duration = .eighth
            .dotted = 0
        elsif .type$ = "eighth"
            .duration = .sixteenth
            .type$ = "16th"
        elsif .type$ = "16th"
            .duration = .thirtysecond
            .type$ = "32nd"
        else
            .duration = 1
            .type$ = "32nd"
        endif
    endif
endproc

procedure getDynamicMarking: .normalized_value
    if .normalized_value >= 0.9
        .marking$ = "ff"
    elsif .normalized_value >= 0.75
        .marking$ = "f"
    elsif .normalized_value >= 0.55
        .marking$ = "mf"
    elsif .normalized_value >= 0.40
        .marking$ = "mp"
    elsif .normalized_value >= 0.25
        .marking$ = "p"
    else
        .marking$ = "pp"
    endif
endproc

procedure createRhythmTextGrid
    selectObject: sound
    tg_rhythm = To TextGrid: "Rhythm Dynamics Beats Measures", ""
    
    tg_current_time = 0
    tg_measure_pos = 0
    tg_measure_num = 1
    
    for n from 1 to note_list_count
        note_dur_sec = note_duration[n] * division_dur
        end_time = tg_current_time + note_dur_sec
        
        if end_time > duration
            end_time = duration
        endif
        
        if tg_current_time < end_time and end_time > 0
            selectObject: tg_rhythm
            
            # Tier 1: Note/Rest value
            if note_type[n] = 0
                label$ = "r"
            else
                label$ = "N"
            endif
            
            if note_dotted[n]
                label$ = label$ + "."
            endif
            
            if note_value_type$[n] = "whole"
                label$ = label$ + "(1)"
            elsif note_value_type$[n] = "half"
                label$ = label$ + "(2)"
            elsif note_value_type$[n] = "quarter"
                label$ = label$ + "(4)"
            elsif note_value_type$[n] = "eighth"
                label$ = label$ + "(8)"
            elsif note_value_type$[n] = "16th"
                label$ = label$ + "(16)"
            elsif note_value_type$[n] = "32nd"
                label$ = label$ + "(32)"
            endif
            
            if end_time < duration
                nocheck Insert boundary: 1, end_time
            endif
            interval_num = Get interval at time: 1, tg_current_time + 0.0001
            nocheck Set interval text: 1, interval_num, label$
            
            # Tier 2: Dynamics
            if note_type[n] = 1 and extract_dynamics
                @getDynamicMarking: note_dynamics[n]
                dyn_label$ = getDynamicMarking.marking$
            else
                dyn_label$ = ""
            endif
            if end_time < duration
                nocheck Insert boundary: 2, end_time
            endif
            nocheck Set interval text: 2, interval_num, dyn_label$
            
            # Tier 3: Beat position
            beat_in_measure = floor(tg_measure_pos / divisions) + 1
            beat_label$ = string$(beat_in_measure)
            if end_time < duration
                nocheck Insert boundary: 3, end_time
            endif
            nocheck Set interval text: 3, interval_num, beat_label$
            
            # Tier 4: Measure numbers
            if tg_measure_pos = 0
                measure_label$ = "M" + string$(tg_measure_num)
            else
                measure_label$ = ""
            endif
            if end_time < duration
                nocheck Insert boundary: 4, end_time
            endif
            nocheck Set interval text: 4, interval_num, measure_label$
        endif
        
        # Update position tracking
        tg_measure_pos = tg_measure_pos + note_duration[n]
        if tg_measure_pos >= divs_per_measure
            tg_measure_pos = tg_measure_pos - divs_per_measure
            tg_measure_num = tg_measure_num + 1
        endif
        
        tg_current_time = end_time
    endfor
    
    selectObject: tg_rhythm
    Rename: sound_name$ + "_rhythm"
endproc