# ============================================================
# Praat AudioTools - Speech to MusicXML Rhythm Extractor v2.9.4
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.9.4 (2026)
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
#   - Claves synthesis: audible rhythmic skeleton (NEW v2.8)
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#   Open the MusicXML output in notation software (MuseScore, Finale, etc.)
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis Toolkit 
#   for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v2.9.4 (2026):
#   - Replaced the main-form outfile field with a true Save As dialog.
#   - When Save MusicXML file is enabled, chooseWriteFile$ opens only after
#     analysis/score generation, with Speech_Rhythm.musicxml as the suggestion.
#   - Cancel from Save As is non-destructive: no file is written and the script
#     continues normally, keeping the generated XML in the Info window.
#
# Changelog v2.9.2 (2026):
#   - Added optional direct MusicXML file saving from the main form.
#   - Uses a native Praat outfile field so the user can choose the destination.
#   - Adds .musicxml automatically if no .xml/.musicxml extension is supplied.
#   - The Info window still prints the generated MusicXML for inspection/copying.
#
# Changelog v2.9.1 (2026):
#   - Fixed method-specific spectral-flux variables for Intensity-only mode.
#     Flux scalars are initialized unconditionally and the candidate test uses
#     nested conditions, avoiding references to undefined flux_cols in Praat.
#
# Changelog v2.9 (2026):
#   - Real multi-bin positive spectral flux for Multi-feature onset detection.
#   - Speech pauses now become rests: note ends follow sounding-interval ends.
#   - Quantized-onset collisions are merged instead of shifting rhythm.
#   - Time-signature denominator now controls measure and beat durations.
#   - Dynamics smoothing is a real local time average around each onset.
#   - Relative dynamics are normalized from onset-level statistics, not silence.
#   - Stereo/multichannel analysis uses the strongest RMS channel.
#   - MusicXML dynamics are placed inside <notations>; split notes are tied.
#   - XML text is escaped and note durations are kept on an integer grid.
#   - Explicit QC metrics and updated AudioTools visualization scaling.
#
# Changelog v2.8 (2026):
#   - NEW: Claves synthesis. After detecting onsets, optionally render
#     a synthetic clave-stick "click" at each onset time, producing an
#     audible rhythmic skeleton aligned with the speech. Each click is
#     a decaying cosine at ~1300 Hz plus an inharmonic partial at
#     ~3500 Hz, with a 60-80 ms decay (configurable). Useful for
#     verifying the detected rhythm by ear.
#   - NEW: Stereo claves option pans accented (downbeat) clicks toward
#     left with the lower clave (~1170 Hz) and unaccented clicks toward
#     right with the higher clave (~1300 Hz), providing two contrasting
#     stick colours for metrical checking. Set Stereo_claves=0 for mono.
#   - NEW: 6th visualization panel showing the synthesized claves
#     waveform aligned with the rhythm row.
# Changelog v2.9.3:
#   - Compact main form for smaller screens. Musical/high-level controls stay
#     in the first dialog; technical quantization, onset, silence, dynamics,
#     stereo-claves and XML-comment controls moved to an optional Advanced
#     settings dialog. Defaults remain identical to v2.9.2.
# Changelog v2.9.3.1:
#   - Fixed Praat form-variable capitalization for MusicXML_file.
#     Praat exposes this field as musicXML_file$, not musicxml_file$.
# ============================================================

clearinfo

# ===== USER FORM =====
form Speech to MusicXML Rhythm v2.9.4
    comment === Rhythm ===
    boolean Auto_detect_tempo 1
    positive Manual_tempo_(BPM) 120
    boolean Auto_detect_meter 1
    natural Time_signature_beats 4
    natural Time_signature_type 4
    optionmenu Detection_method: 1
        option Intensity only
        option Multi-feature (intensity + spectral)
        option Syllable nuclei

    comment === Output ===
    boolean Render_claves 1
    optionmenu Output_pitch: 1
        option C4 (middle C)
        option B3 (unpitched percussion)
        option E4 (speech line)
    boolean Create_TextGrid 1
    boolean Save_MusicXML_file 1
    comment Save dialog opens after analysis

    comment === Optional ===
    boolean Edit_advanced_settings 0
endform

# Defaults for controls moved out of the main form. These preserve v2.9.2
# behaviour when Advanced settings is not opened.
pulse_unit = 3
divisions_per_quarter = 8
allow_dotted_notes = 1
compound_meter = 0
min_onset_separation = 0.08
prominence_threshold = 2.5
min_silent_duration = 0.10
min_sounding_duration = 0.08
silence_threshold = -25
extract_dynamics = 1
dynamics_smoothing = 0.10
stereo_claves = 1
include_comments = 1

if edit_advanced_settings
    beginPause: "Speech Rhythm - Advanced settings"
        comment: "Quantization"
        choice: "Pulse unit", pulse_unit
            option: "Whole note"
            option: "Half note"
            option: "Quarter note"
            option: "Eighth note"
            option: "16th note"
        natural: "Divisions per quarter", divisions_per_quarter
        boolean: "Allow dotted notes", allow_dotted_notes
        boolean: "Compound meter", compound_meter

        comment: "Detection details"
        positive: "Min onset separation (s)", min_onset_separation
        positive: "Prominence threshold (dB)", prominence_threshold
        positive: "Min silent duration (s)", min_silent_duration
        positive: "Min sounding duration (s)", min_sounding_duration
        integer: "Silence threshold (dB)", silence_threshold

        comment: "Dynamics / verification"
        boolean: "Extract dynamics", extract_dynamics
        positive: "Dynamics smoothing (s)", dynamics_smoothing
        boolean: "Stereo claves", stereo_claves
        boolean: "Include XML comments", include_comments
    endPause: "Continue", 1
endif

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
render_claves = render_claves
stereo_claves = stereo_claves
# Claves voice constants. Edit here if you want a different timbre:
# higher claves_pitch = thinner sound; longer decay = more woody/sustained.
claves_pitch = 1300
claves_decay_ms = 70
output_pitch = output_pitch
include_comments = include_comments
create_textgrid_output = create_TextGrid
save_musicxml = save_MusicXML_file

# This version guarantees exact standard note values through 32nd notes.
# Manual time-signature denominators are therefore limited to conventional
# powers of two through 32.
if not auto_meter
    valid_beat_type = (time_sig_type = 1 or time_sig_type = 2 or time_sig_type = 4 or time_sig_type = 8 or time_sig_type = 16 or time_sig_type = 32)
    if not valid_beat_type
        exitScript: "Time signature denominator must be 1, 2, 4, 8, 16, or 32."
    endif
endif

# ===== PITCH / STAFF SETTINGS =====
output_unpitched = 0
if output_pitch = 1
    pitch_step$ = "C"
    pitch_octave = 4
elsif output_pitch = 2
    pitch_step$ = "B"
    pitch_octave = 3
    output_unpitched = 1
else
    pitch_step$ = "E"
    pitch_octave = 4
endif

# ===== GET SELECTED SOUND =====
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif
sound = selected("Sound")
sound_name$ = selected$("Sound")
selectObject: sound
sound_tmin = Get start time
sound_tmax = Get end time
duration = sound_tmax - sound_tmin
sample_rate = Get sampling frequency
n_channels = Get number of channels

# Analysis uses one representative channel. This avoids phase-cancelling
# stereo fold-down while leaving the user's original Sound untouched.
analysis_sound = sound
analysis_is_copy = 0
analysis_channel = 1
if n_channels > 1
    best_rms = -1
    for ch from 1 to n_channels
        selectObject: sound
        tmp_channel = Extract one channel: ch
        channel_rms = Get root-mean-square: sound_tmin, sound_tmax
        if channel_rms > best_rms
            best_rms = channel_rms
            analysis_channel = ch
        endif
        removeObject: tmp_channel
    endfor
    selectObject: sound
    analysis_sound = Extract one channel: analysis_channel
    analysis_is_copy = 1
endif

# ===== CREATE ANALYSIS OBJECTS =====
selectObject: analysis_sound
intensity = To Intensity: 100, 0.01, "yes"
intensity_min = Get minimum: 0, 0, "Parabolic"
intensity_max = Get maximum: 0, 0, "Parabolic"

# ===== DETECT SILENCE/SPEECH INTERVALS =====
selectObject: analysis_sound
textgrid = To TextGrid (silences): 100, 0, silence_threshold, min_silent_dur, min_sounding_dur, "silent", "sounding"

# ===== TRUE SPECTRAL FLUX (for multi-feature detection) =====
# Positive spectral flux compares normalized adjacent spectra over all bins.
# It is precomputed once so candidate testing stays cheap.
# Initialise all flux scalars even when another detection method is selected.
# Praat does not safely short-circuit references to variables that do not exist.
flux_cols = 0
flux_rows = 0
flux_mean = 0
flux_sd = 0
flux_threshold = 0
flux_t1 = sound_tmin
flux_dx = 0.005
if detection_method = 2
    selectObject: analysis_sound
    flux_max_freq = min(5000, sample_rate * 0.49)
    spectrogram = To Spectrogram: 0.015, flux_max_freq, 0.005, 20, "Gaussian"
    spg_matrix = To Matrix
    flux_cols = Get number of columns
    flux_rows = Get number of rows

    flux_mean = 0
    flux_sd = 0
    flux_threshold = 0
    flux_t1 = sound_tmin
    flux_dx = 0.005

    if flux_cols >= 2
        flux_t1 = Get x of column: 1
        flux_t2 = Get x of column: 2
        flux_dx = flux_t2 - flux_t1
        if flux_dx <= 0
            flux_dx = 0.005
        endif

        prev_sum = 0
        for r from 1 to flux_rows
            v = Get value in cell: r, 1
            if v = undefined
                v = 0
            elsif v < 0
                v = 0
            endif
            flux_prev[r] = v
            prev_sum = prev_sum + v
        endfor

        flux_val[1] = 0
        flux_sum = 0
        flux_sum2 = 0
        for c from 2 to flux_cols
            cur_sum = 0
            for r from 1 to flux_rows
                v = Get value in cell: r, c
                if v = undefined
                    v = 0
                elsif v < 0
                    v = 0
                endif
                flux_cur[r] = v
                cur_sum = cur_sum + v
            endfor

            fsum = 0
            for r from 1 to flux_rows
                prev_norm = flux_prev[r] / (prev_sum + 1e-30)
                cur_norm = flux_cur[r] / (cur_sum + 1e-30)
                delta = cur_norm - prev_norm
                if delta > 0
                    fsum = fsum + delta
                endif
                flux_prev[r] = flux_cur[r]
            endfor
            flux_val[c] = fsum
            flux_sum = flux_sum + fsum
            flux_sum2 = flux_sum2 + fsum * fsum
            prev_sum = cur_sum
        endfor

        n_flux_stats = flux_cols - 1
        flux_mean = flux_sum / n_flux_stats
        flux_var = flux_sum2 / n_flux_stats - flux_mean * flux_mean
        if flux_var < 0
            flux_var = 0
        endif
        flux_sd = sqrt(flux_var)
        flux_threshold = flux_mean + 0.25 * flux_sd
    endif
endif

# ===== ONSET DETECTION =====
max_onsets = 2000
for i from 1 to max_onsets
    onset_time[i] = 0
    onset_intensity[i] = 0
endfor

onset_count = 0
onset_overflow = 0

selectObject: textgrid
n_intervals = Get number of intervals: 1

# ----- METHOD 1 & 2: Intensity peaks, optionally confirmed by spectral flux -----
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
                    t_m1 = t - adaptive_window / 2
                    t_p1 = t + adaptive_window / 2
                    int_m1 = Get value at time: t_m1, "Cubic"
                    int_p1 = Get value at time: t_p1, "Cubic"

                    if int_m1 <> undefined and int_p1 <> undefined
                        is_peak = (int_val > int_m1) and (int_val > int_p1)

                        if is_peak and (t - last_onset >= min_separation)
                            alpha = int_m1
                            beta = int_val
                            gamma = int_p1

                            if (alpha - 2 * beta + gamma) <> 0
                                p = 0.5 * (alpha - gamma) / (alpha - 2 * beta + gamma)
                                # Parabolic interpolation is only trusted locally.
                                p = max(-1, min(1, p))
                                refined_t = t + p * (adaptive_window / 2)
                                refined_int = beta - 0.25 * (alpha - gamma) * p
                            else
                                refined_t = t
                                refined_int = int_val
                            endif

                            window_start = max(t - 0.15, t_start)
                            window_end = min(t + 0.15, t_end)
                            n_samples = 15
                            sample_step = (window_end - window_start) / n_samples

                            for ss from 1 to n_samples
                                sample_t = window_start + (ss - 0.5) * sample_step
                                sample_vals[ss] = Get value at time: sample_t, "Cubic"
                                if sample_vals[ss] = undefined
                                    sample_vals[ss] = int_val
                                endif
                            endfor

                            # Small fixed-size sort for a local median.
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
                                if flux_cols >= 2
                                    flux_col = round((refined_t - flux_t1) / flux_dx) + 1
                                    flux_col = max(2, min(flux_cols, flux_col))
                                    candidate_flux = flux_val[flux_col]
                                    spectral_onset = (candidate_flux >= flux_threshold)
                                endif
                            endif

                            if prominence >= prominence_threshold and spectral_onset
                                if onset_count < max_onsets
                                    onset_count = onset_count + 1
                                    onset_time[onset_count] = refined_t
                                    onset_intensity[onset_count] = refined_int
                                    last_onset = refined_t
                                else
                                    onset_overflow = 1
                                endif
                            endif
                        endif
                    endif
                endif

                t = t + 0.005
            endwhile
        endif
    endfor

# ----- METHOD 3: Voiced intensity nuclei -----
elsif detection_method = 3

    selectObject: analysis_sound
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
                        left_t = max(t_start, local_max_t - 0.06)
                        right_t = min(t_end, local_max_t + 0.06)
                        left_int = Get value at time: left_t, "Cubic"
                        right_int = Get value at time: right_t, "Cubic"
                        if left_int = undefined
                            left_int = local_max_int
                        endif
                        if right_int = undefined
                            right_int = local_max_int
                        endif
                        nucleus_prominence = local_max_int - 0.5 * (left_int + right_int)

                        selectObject: pitch_obj
                        f0 = Get value at time: local_max_t, "Hertz", "Linear"
                        selectObject: intensity

                        if f0 <> undefined and nucleus_prominence >= prominence_threshold
                            if onset_count < max_onsets
                                onset_count = onset_count + 1
                                onset_time[onset_count] = local_max_t
                                onset_intensity[onset_count] = local_max_int
                                last_onset = local_max_t
                            else
                                onset_overflow = 1
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

    removeObject: intensity, textgrid
    if detection_method = 2
        removeObject: spg_matrix, spectrogram
    endif
    if analysis_is_copy
        removeObject: analysis_sound
    endif
    exitScript()
endif

# ===== ONSET DYNAMICS + SOUNDING-END TIMES =====
# Dynamics are relative to detected onset peaks, not to global silence.
dyn_sum = 0
dyn_sum2 = 0
dyn_min = onset_intensity[1]
dyn_max = onset_intensity[1]
for i from 1 to onset_count
    v = onset_intensity[i]
    dyn_sum = dyn_sum + v
    dyn_sum2 = dyn_sum2 + v * v
    if v < dyn_min
        dyn_min = v
    endif
    if v > dyn_max
        dyn_max = v
    endif
endfor
dyn_mean = dyn_sum / onset_count
dyn_var = dyn_sum2 / onset_count - dyn_mean * dyn_mean
if dyn_var < 0
    dyn_var = 0
endif
dyn_sd = sqrt(dyn_var)
dyn_low = max(dyn_min, dyn_mean - 1.5 * dyn_sd)
dyn_high = min(dyn_max, dyn_mean + 1.5 * dyn_sd)
if dyn_high - dyn_low < 3
    dyn_low = dyn_min
    dyn_high = dyn_max
endif
if dyn_high - dyn_low < 0.5
    dynamics_flat = 1
else
    dynamics_flat = 0
endif

for i from 1 to onset_count
    # End of the sounding interval containing this onset.
    selectObject: textgrid
    interval_idx = Get interval at time: 1, onset_time[i]
    interval_label$ = Get label of interval: 1, interval_idx
    if interval_label$ = "sounding"
        onset_sound_end[i] = Get end time of interval: 1, interval_idx
    else
        onset_sound_end[i] = min(sound_tmax, onset_time[i] + min_separation)
    endif

    if extract_dynamics
        selectObject: intensity
        n_dyn_samples = 7
        dyn_acc = 0
        dyn_n = 0
        dyn_half = dynamics_smoothing / 2
        for ds from 1 to n_dyn_samples
            if n_dyn_samples > 1
                frac = (ds - 1) / (n_dyn_samples - 1)
            else
                frac = 0.5
            endif
            dyn_t = onset_time[i] - dyn_half + frac * dynamics_smoothing
            dyn_t = max(sound_tmin, min(sound_tmax, dyn_t))
            dyn_v = Get value at time: dyn_t, "Cubic"
            if dyn_v <> undefined
                dyn_acc = dyn_acc + dyn_v
                dyn_n = dyn_n + 1
            endif
        endfor
        if dyn_n > 0
            dyn_smoothed = dyn_acc / dyn_n
        else
            dyn_smoothed = onset_intensity[i]
        endif
        if dynamics_flat
            onset_dynamic[i] = 0.5
        else
            onset_dynamic[i] = (dyn_smoothed - dyn_low) / (dyn_high - dyn_low)
            onset_dynamic[i] = max(0, min(1, onset_dynamic[i]))
        endif
    else
        onset_dynamic[i] = 0.5
    endif
endfor

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
    # Manual BPM refers to the selected pulse unit; internally all timing is
    # converted to quarter-note BPM so measure arithmetic stays consistent.
    if pulse_unit = 1
        tempo = manual_tempo * 4
        pulse_name$ = "whole note (manual)"
    elsif pulse_unit = 2
        tempo = manual_tempo * 2
        pulse_name$ = "half note (manual)"
    elsif pulse_unit = 3
        tempo = manual_tempo
        pulse_name$ = "quarter note (manual)"
    elsif pulse_unit = 4
        tempo = manual_tempo / 2
        pulse_name$ = "eighth note (manual)"
    else
        tempo = manual_tempo / 4
        pulse_name$ = "16th note (manual)"
    endif
    tempo_confidence = 1.0
    dominant_ioi = 0
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
# MusicXML duration values are most interoperable on an integer grid.
# This converter supports through 32nd notes, so use a multiple of 8.
requested_divisions = round(divisions)
if requested_divisions < 8
    requested_divisions = 8
endif
if requested_divisions mod 8 <> 0
    divisions = ceiling(requested_divisions / 8) * 8
    divisions_adjusted = 1
else
    divisions = requested_divisions
    divisions_adjusted = 0
endif

quarter_dur = 60.0 / tempo
division_dur = quarter_dur / divisions

# The denominator is musically active: 3/8, 6/8, 5/16, etc. no longer
# inherit quarter-note measure lengths.
notated_beat_quarters = 4.0 / time_sig_type
notated_beat_dur = quarter_dur * notated_beat_quarters
divs_per_notated_beat = round(divisions * notated_beat_quarters)
if divs_per_notated_beat < 1
    divs_per_notated_beat = 1
endif
divs_per_measure = time_sig_beats * divs_per_notated_beat
measure_dur = divs_per_measure * division_dur

if compound_meter and time_sig_beats mod 3 = 0
    pulse_group_divs = 3 * divs_per_notated_beat
    pulse_group_dur = pulse_group_divs * division_dur
else
    pulse_group_divs = divs_per_notated_beat
    pulse_group_dur = notated_beat_dur
endif

divs_per_whole = divisions * 4
divs_per_half = divisions * 2
divs_per_quarter = divisions
divs_per_eighth = divisions / 2
divs_per_16th = divisions / 4
divs_per_32nd = divisions / 8

# ===== QUANTIZE ONSETS =====
# Raw detection times are retained for QC/visualization. Onsets that land on
# the same grid position are merged, keeping the stronger candidate.
rhythm_onset_count = 0
for i from 1 to onset_count
    rel_onset = onset_time[i] - sound_tmin
    raw_divs = rel_onset / division_dur
    q_div = round(raw_divs)
    if q_div < 0
        q_div = 0
    endif
    quantized_divs[i] = q_div
    quantization_error[i] = abs(raw_divs - q_div) * division_dur

    rel_sound_end = onset_sound_end[i] - sound_tmin
    q_end = round(rel_sound_end / division_dur)
    if q_end <= q_div
        q_end = q_div + 1
    endif

    if rhythm_onset_count = 0 or q_div > rhythm_div[rhythm_onset_count]
        rhythm_onset_count = rhythm_onset_count + 1
        rhythm_div[rhythm_onset_count] = q_div
        rhythm_time[rhythm_onset_count] = rel_onset
        rhythm_intensity[rhythm_onset_count] = onset_intensity[i]
        rhythm_dynamic[rhythm_onset_count] = onset_dynamic[i]
        rhythm_sound_end_div[rhythm_onset_count] = q_end
    else
        # Quantized collision: retain the acoustically stronger onset.
        if onset_intensity[i] > rhythm_intensity[rhythm_onset_count]
            rhythm_time[rhythm_onset_count] = rel_onset
            rhythm_intensity[rhythm_onset_count] = onset_intensity[i]
            rhythm_dynamic[rhythm_onset_count] = onset_dynamic[i]
            rhythm_sound_end_div[rhythm_onset_count] = q_end
        endif
    endif
endfor

# ===== BUILD NOTE / REST LIST =====
max_notes = 10000
note_list_count = 0
note_overflow = 0
current_div = 0

for i from 1 to rhythm_onset_count
    target_div = rhythm_div[i]

    # Silence before this onset becomes a real rest.
    rest_dur = target_div - current_div
    if rest_dur > 0
        @addToNoteList: 0, rest_dur, current_div * division_dur, 0
    endif

    # The note ends at the next onset or at the end of its sounding interval,
    # whichever comes first. This preserves speech pauses.
    note_end_div = rhythm_sound_end_div[i]
    if i < rhythm_onset_count
        if rhythm_div[i + 1] < note_end_div
            note_end_div = rhythm_div[i + 1]
        endif
    endif
    if note_end_div <= target_div
        note_end_div = target_div + 1
    endif
    note_dur = note_end_div - target_div

    @addToNoteList: 1, note_dur, target_div * division_dur, rhythm_dynamic[i]
    current_div = target_div + note_dur
endfor

# Preserve any trailing silence after the final sounding interval.
end_div = round(duration / division_dur)
if current_div < end_div
    @addToNoteList: 0, end_div - current_div, current_div * division_dur, 0
endif

if note_overflow
    exitScript: "Rhythm event list exceeded " + string$(max_notes) + " entries. Increase the rhythmic grid size or shorten the selection."
endif

# =====================================================================
# CLAVES SYNTHESIS
# =====================================================================
# CLAVES SYNTHESIS (NEW v2.8)
# =====================================================================
# Render an audible rhythmic skeleton: at each detected onset time we
# write a synthetic claves "click" into a pre-allocated Sound buffer.
# Each click is a decaying cosine at the claves fundamental + an
# inharmonic upper partial at 2.7x. Cosine (not sine) so the wave
# starts at full amplitude at t0 — gives the sharp claves attack.
# Stereo mode pans accented downbeats slightly L (lower clave) and
# unaccented hits slightly R (higher clave), giving metrical accents
# two contrasting synthetic stick colours.
#
# Onsets are sparse (<= ~10/sec for speech) so per-onset Formula (part)
# writes are cheap. The buffer is pre-allocated with "0" formula, so
# segments outside any click region remain silent.

if render_claves
    selectObject: sound
    fs_claves = Get sampling frequency

    # Two clave pitches (lower wood / higher wood) - 1 semitone apart.
    # f_lo = ~1226 Hz at default 1300 Hz pitch; fp = inharmonic upper partial at 2.7x
    f_hi = min(claves_pitch, fs_claves * 0.35)
    f_lo = f_hi * 0.943
    fp_lo = min(f_lo * 2.7, fs_claves * 0.45)
    fp_hi = min(f_hi * 2.7, fs_claves * 0.45)

    # Decay rate: -60 dB at decay_sec means decay_rate = ln(1000)/decay_sec = 6.9/decay_sec
    decay_sec = claves_decay_ms / 1000
    decay_rate = 6.9 / decay_sec
    # Partial decays a bit faster (clave wood is "drier" at higher freq)
    decay_rate_p = decay_rate * 1.5
    # Click duration: 1.5 * decay_sec is at -90 dB, plenty
    click_dur = decay_sec * 1.5

    # Pre-allocate output buffer (1 or 2 channels)
    if stereo_claves
        claves_sound = Create Sound from formula:
            ... sound_name$ + "_claves",
            ... 2, 0, duration, fs_claves, "0"
    else
        claves_sound = Create Sound from formula:
            ... sound_name$ + "_claves",
            ... 1, 0, duration, fs_claves, "0"
    endif

    appendInfoLine: ""
    appendInfoLine: "Synthesizing claves rhythmic skeleton..."

    n_clicks_written = 0

    for i from 1 to onset_count
        t0 = onset_time[i] - sound_tmin

        # Determine accent: is this near a downbeat?
        beat_pos = t0 / measure_dur
        beat_in_measure = beat_pos - floor(beat_pos)
        # Within the first 8% of a measure counts as downbeat
        is_downbeat = (beat_in_measure < 0.08)

        # Accent intensity uses the same onset-level normalized dynamics
        # as the MusicXML rhythm.
        if extract_dynamics
            dyn_norm_clave = onset_dynamic[i]
        else
            dyn_norm_clave = 0.7
        endif

        # Click amplitude scales with dynamic
        if is_downbeat
            click_amp = 0.55 + 0.40 * dyn_norm_clave
            f0_use = f_lo
            fp_use = fp_lo
            # Slightly louder on the L side
            ampL = 1.00
            ampR = 0.55
        else
            click_amp = 0.40 + 0.40 * dyn_norm_clave
            f0_use = f_hi
            fp_use = fp_hi
            ampL = 0.55
            ampR = 1.00
        endif

        click_end = t0 + click_dur
        if click_end > duration
            click_end = duration
        endif
        # Skip if there's no room for the click (onset at very end of input)
        if click_end > t0
            f0_str$ = fixed$(f0_use, 4)
            fp_str$ = fixed$(fp_use, 4)
            d_str$ = fixed$(decay_rate, 4)
            dp_str$ = fixed$(decay_rate_p, 4)
            t0_str$ = fixed$(t0, 6)
            amp_str$ = fixed$(click_amp, 4)

            # Click expression: cos(2*pi*f0*(x-t0)) * exp(-decay*(x-t0))
            # plus 0.35 * sin(2*pi*fp*(x-t0)) * exp(-decay_p*(x-t0))
            click$ = amp_str$ + " * (cos(2*pi*" + f0_str$
                ... + "*(x-" + t0_str$ + ")) * exp(-" + d_str$
                ... + "*(x-" + t0_str$ + "))"
                ... + " + 0.35 * sin(2*pi*" + fp_str$
                ... + "*(x-" + t0_str$ + ")) * exp(-" + dp_str$
                ... + "*(x-" + t0_str$ + ")))"

            if stereo_claves
                ampL_str$ = fixed$(ampL, 3)
                ampR_str$ = fixed$(ampR, 3)
                selectObject: claves_sound
                Formula (part): t0, click_end, 1, 1,
                    ... "self + " + ampL_str$ + " * (" + click$ + ")"
                Formula (part): t0, click_end, 2, 2,
                    ... "self + " + ampR_str$ + " * (" + click$ + ")"
            else
                selectObject: claves_sound
                Formula (part): t0, click_end, 1, 1,
                    ... "self + (" + click$ + ")"
            endif

            n_clicks_written = n_clicks_written + 1
        endif
    endfor

    selectObject: claves_sound
    Scale peak: 0.95

    appendInfoLine: "  ", n_clicks_written, " claves clicks written at ",
        ... fixed$(claves_pitch, 0), " Hz, decay ", claves_decay_ms, " ms"
endif


# Escape element text and protect XML comments from "--".
safe_sound_name$ = replace$(sound_name$, "&", "&amp;", 0)
safe_sound_name$ = replace$(safe_sound_name$, "<", "&lt;", 0)
safe_sound_name$ = replace$(safe_sound_name$, ">", "&gt;", 0)
comment_sound_name$ = replace$(sound_name$, "--", "- -", 0)

xml$ = "<?xml version=""1.0"" encoding=""UTF-8""?>" + newline$
xml$ = xml$ + "<!DOCTYPE score-partwise PUBLIC ""-//Recordare//DTD MusicXML 3.1 Partwise//EN"" ""http://www.musicxml.org/dtds/partwise.dtd"">" + newline$
xml$ = xml$ + "<score-partwise version=""3.1"">" + newline$

if include_comments
    xml$ = xml$ + "  <!-- Generated by Praat AudioTools v2.9.1 -->" + newline$
    xml$ = xml$ + "  <!-- Source: " + comment_sound_name$ + " -->" + newline$
    if auto_tempo
        xml$ = xml$ + "  <!-- Auto-detected tempo: " + string$(tempo) + " BPM (confidence: " + fixed$(tempo_confidence * 100, 0) + "%) -->" + newline$
    endif
    xml$ = xml$ + "  <!-- Onsets detected: " + string$(onset_count) + " -->" + newline$
endif

xml$ = xml$ + "  <work>" + newline$
xml$ = xml$ + "    <work-title>" + safe_sound_name$ + " - Rhythm</work-title>" + newline$
xml$ = xml$ + "  </work>" + newline$

xml$ = xml$ + "  <identification>" + newline$
xml$ = xml$ + "    <creator type=""composer"">Speech Analysis</creator>" + newline$
xml$ = xml$ + "    <encoding>" + newline$
xml$ = xml$ + "      <software>Praat AudioTools v2.9.1</software>" + newline$
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
if output_unpitched
    xml$ = xml$ + "          <sign>percussion</sign>" + newline$
else
    xml$ = xml$ + "          <sign>G</sign>" + newline$
    xml$ = xml$ + "          <line>2</line>" + newline$
endif
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
    
    @emitXMLElement: type$, note_duration[n], note_dynamics[n], note_tie_prev[n], note_tie_next[n], note_show_dynamic[n]
endfor

# Fill final measure
final_measure_remaining = divs_per_measure - measure_position
if final_measure_remaining > 0 and final_measure_remaining < divs_per_measure
    @emitXMLElement: "rest", final_measure_remaining, 0, 0, 0, 0
endif

xml$ = xml$ + "    </measure>" + newline$
xml$ = xml$ + "  </part>" + newline$
xml$ = xml$ + "</score-partwise>"

# ===== CREATE RHYTHM TEXTGRID =====
if create_textgrid_output
    @createRhythmTextGrid
endif

# ============================================================
# VISUALIZATION
# ============================================================

appendInfoLine: ""
appendInfoLine: "Creating rhythm visualization..."

Erase all

# --- Calculate layout ---
viz_duration = duration
if viz_duration > 30
    viz_duration = 30
    appendInfoLine: "  (Showing first 30 seconds)"
endif

# --- TITLE / METADATA ---
Select outer viewport: 0, 8, 0, 0.45
Axes: 0, 1, 0, 1
Font size: 10
Colour: "Black"
Text: 0.5, "centre", 0.68, "half", "##Speech to Rhythm v2.9.1## | " + sound_name$
Font size: 7
Colour: "{0.35, 0.35, 0.45}"
Text: 0.5, "centre", 0.22, "half", "q=" + string$(tempo) + " BPM | " + string$(time_sig_beats) + "/" + string$(time_sig_type) + " | " + string$(onset_count) + " detected -> " + string$(rhythm_onset_count) + " quantized onsets"

# --- WAVEFORM WITH RAW DETECTED ONSETS ---
Select outer viewport: 0, 8, 0.5, 1.7
Select inner viewport: 0.8, 7.8, 0.6, 1.6
viz_abs_start = sound_tmin
viz_abs_end = sound_tmin + viz_duration

selectObject: analysis_sound
wave_peak = Get absolute extremum: viz_abs_start, viz_abs_end, "Sinc70"
if wave_peak = undefined
    wave_peak = 1
elsif wave_peak <= 0
    wave_peak = 1
endif
wave_peak = wave_peak * 1.03
Colour: "{0.5, 0.6, 0.75}"
Draw: viz_abs_start, viz_abs_end, -wave_peak, wave_peak, "no", "Curve"

Select inner viewport: 0.8, 7.8, 0.6, 1.6
Axes: viz_abs_start, viz_abs_end, -wave_peak, wave_peak
Colour: "{0.9, 0.25, 0.25}"
Line width: 1.5
for i from 1 to onset_count
    if onset_time[i] >= viz_abs_start and onset_time[i] <= viz_abs_end
        Draw line: onset_time[i], -0.92 * wave_peak, onset_time[i], 0.92 * wave_peak
    endif
endfor

Select inner viewport: 0.8, 7.8, 0.6, 1.6
Axes: viz_abs_start, viz_abs_end, -wave_peak, wave_peak
Colour: "Black"
Line width: 0.5
Draw inner box

Font size: 7
Select outer viewport: 0, 0.8, 0.5, 1.7
Axes: 0, 1, 0, 1
Colour: "{0.3, 0.4, 0.55}"
Text: 0.95, "right", 0.6, "half", "Waveform"
Font size: 5
Colour: "{0.5, 0.5, 0.55}"
if n_channels > 1
    Text: 0.95, "right", 0.3, "half", "ch " + string$(analysis_channel)
else
    Text: 0.95, "right", 0.3, "half", string$(onset_count) + " onsets"
endif

# --- INTENSITY WITH PEAKS ---
Select outer viewport: 0, 8, 1.8, 2.8
Select inner viewport: 0.8, 7.8, 1.9, 2.7
Axes: viz_abs_start, viz_abs_end, intensity_min - 5, intensity_max + 5
Paint rectangle: "{0.97, 0.98, 1.0}", viz_abs_start, viz_abs_end, intensity_min - 5, intensity_max + 5

Select inner viewport: 0.8, 7.8, 1.9, 2.7
Axes: viz_abs_start, viz_abs_end, intensity_min - 5, intensity_max + 5
selectObject: intensity
Colour: "{0.4, 0.6, 0.8}"
Line width: 1.5
Draw: viz_abs_start, viz_abs_end, intensity_min - 5, intensity_max + 5, "no"

Select inner viewport: 0.8, 7.8, 1.9, 2.7
Axes: viz_abs_start, viz_abs_end, intensity_min - 5, intensity_max + 5
for i from 1 to onset_count
    if onset_time[i] >= viz_abs_start and onset_time[i] <= viz_abs_end
        Paint rectangle: "{0.9, 0.4, 0.4}", onset_time[i] - 0.008, onset_time[i] + 0.008, onset_intensity[i] - 1.5, onset_intensity[i] + 1.5
    endif
endfor

Select inner viewport: 0.8, 7.8, 1.9, 2.7
Axes: viz_abs_start, viz_abs_end, intensity_min - 5, intensity_max + 5
Colour: "Black"
Line width: 0.5
Draw inner box

Font size: 7
Select outer viewport: 0, 0.8, 1.8, 2.8
Axes: 0, 1, 0, 1
Colour: "{0.3, 0.5, 0.7}"
Text: 0.95, "right", 0.6, "half", "Intensity"
Font size: 5
Colour: "{0.5, 0.5, 0.55}"
Text: 0.95, "right", 0.3, "half", "dB"

# --- RHYTHMIC NOTATION ---
Select outer viewport: 0, 8, 2.9, 4.3
Select inner viewport: 0.8, 7.8, 3.0, 4.2

Axes: 0, viz_duration, 0, 2

# Background with measure grid
Paint rectangle: "{0.99, 0.99, 0.98}", 0, viz_duration, 0, 2

# Draw measure lines
Colour: "{0.75, 0.75, 0.8}"
Line width: 1
measure_time = 0
measure_num = 1
while measure_time < viz_duration
    Draw line: measure_time, 0, measure_time, 2
    
    # Measure number
    Font size: 5
    Colour: "{0.5, 0.5, 0.6}"
    Text: measure_time + 0.02, "left", 1.9, "half", string$(measure_num)
    
    measure_time = measure_time + measure_dur
    measure_num = measure_num + 1
endwhile

# Draw beat lines (lighter)
Colour: "{0.88, 0.88, 0.9}"
Line width: 0.5
Dotted line
beat_time = 0
while beat_time < viz_duration
    Draw line: beat_time, 0.3, beat_time, 1.7
    beat_time = beat_time + notated_beat_dur
endwhile
Solid line

# Draw notes and rests
current_time = 0
for n from 1 to note_list_count
    note_dur_sec = note_duration[n] * division_dur
    end_time = current_time + note_dur_sec
    
    if current_time < viz_duration
        if end_time > viz_duration
            end_time = viz_duration
        endif
        
        if note_type[n] = 1
            # Note - filled rectangle
            # Height based on dynamics
            if extract_dynamics
                height = 0.4 + note_dynamics[n] * 0.8
            else
                height = 0.8
            endif
            
            y_center = 1.0
            y_bottom = y_center - height/2
            y_top = y_center + height/2
            
            # Color by note value
            if note_value_type$[n] = "whole"
                colour$ = "{0.3, 0.5, 0.8}"
            elsif note_value_type$[n] = "half"
                colour$ = "{0.4, 0.6, 0.75}"
            elsif note_value_type$[n] = "quarter"
                colour$ = "{0.5, 0.7, 0.6}"
            elsif note_value_type$[n] = "eighth"
                colour$ = "{0.7, 0.65, 0.5}"
            elsif note_value_type$[n] = "16th"
                colour$ = "{0.8, 0.55, 0.45}"
            else
                colour$ = "{0.85, 0.45, 0.4}"
            endif
            
            Paint rectangle: colour$, current_time + 0.002, end_time - 0.002, y_bottom, y_top
            
            # Dotted note marker
            if note_dotted[n]
                Colour: "White"
                Font size: 6
                midX = (current_time + end_time) / 2
                Text: midX, "centre", y_center, "half", "•"
            endif
            
            # Outline
            Colour: "{0.3, 0.3, 0.4}"
            Line width: 0.5
            Draw rectangle: current_time + 0.002, end_time - 0.002, y_bottom, y_top
            
        else
            # Rest - outlined rectangle with diagonal
            Colour: "{0.8, 0.8, 0.85}"
            Line width: 0.5
            y_bottom = 0.6
            y_top = 1.4
            
            Draw rectangle: current_time + 0.005, end_time - 0.005, y_bottom, y_top
            
            # Diagonal line for rest
            Colour: "{0.75, 0.75, 0.8}"
            Draw line: current_time + 0.005, y_bottom, end_time - 0.005, y_top
        endif
    endif
    
    current_time = end_time
endfor

Colour: "Black"
Line width: 0.5
Draw inner box

Font size: 7
Select outer viewport: 0, 0.8, 2.9, 4.3
Axes: 0, 1, 0, 1
Colour: "{0.3, 0.4, 0.5}"
Text: 0.95, "right", 0.6, "half", "Rhythm"
Font size: 5
Colour: "{0.5, 0.5, 0.55}"
Text: 0.95, "right", 0.3, "half", string$(note_list_count) + " events"

# --- CLAVES WAVEFORM ---
if render_claves
    Select outer viewport: 0, 8, 4.4, 5.2
    Select inner viewport: 0.8, 7.8, 4.5, 5.1
    Axes: 0, viz_duration, -1, 1
    Paint rectangle: "{0.99, 0.98, 0.96}", 0, viz_duration, -1, 1

    claves_viz_sound = claves_sound
    claves_viz_is_copy = 0
    if stereo_claves
        selectObject: claves_sound
        claves_viz_sound = Extract one channel: 1
        claves_viz_is_copy = 1
    endif

    Select inner viewport: 0.8, 7.8, 4.5, 5.1
    Axes: 0, viz_duration, -1, 1
    selectObject: claves_viz_sound
    Colour: "{0.55, 0.40, 0.25}"
    Line width: 1.0
    Draw: 0, viz_duration, -1, 1, "no", "Curve"

    Select inner viewport: 0.8, 7.8, 4.5, 5.1
    Axes: 0, viz_duration, -1, 1
    Colour: "Black"
    Line width: 0.5
    Draw inner box

    if claves_viz_is_copy
        removeObject: claves_viz_sound
    endif

    Font size: 7
    Select outer viewport: 0, 0.8, 4.4, 5.2
    Axes: 0, 1, 0, 1
    Colour: "{0.5, 0.35, 0.2}"
    Text: 0.95, "right", 0.6, "half", "Claves"
    Font size: 5
    Colour: "{0.5, 0.5, 0.55}"
    if stereo_claves
        Text: 0.95, "right", 0.3, "half", "L shown"
    else
        Text: 0.95, "right", 0.3, "half", "mono"
    endif
endif

# --- DYNAMICS CONTOUR ---
# v2.9: viewport y shifts by 0.9 if claves panel is rendered above
if render_claves
    dyn_top = 5.3
    dyn_bot = 6.1
else
    dyn_top = 4.4
    dyn_bot = 5.2
endif

if extract_dynamics
    Select outer viewport: 0, 8, dyn_top, dyn_bot
    Select inner viewport: 0.8, 7.8, dyn_top + 0.1, dyn_bot - 0.1
    
    Axes: 0, viz_duration, 0, 1
    
    Paint rectangle: "{0.98, 0.97, 0.99}", 0, viz_duration, 0, 1
    
    # Draw dynamics as stepped line based on notes
    Colour: "{0.6, 0.4, 0.7}"
    Line width: 2
    
    current_time = 0
    for n from 1 to note_list_count
        note_dur_sec = note_duration[n] * division_dur
        end_time = current_time + note_dur_sec
        
        if current_time < viz_duration and note_type[n] = 1
            if end_time > viz_duration
                end_time = viz_duration
            endif
            
            dyn_val = note_dynamics[n]
            Draw line: current_time, dyn_val, end_time, dyn_val
        endif
        
        current_time = end_time
    endfor
    
    # Dynamic level markers
    Font size: 4
    Colour: "{0.6, 0.6, 0.65}"
    Text: viz_duration * 0.995, "right", 0.92, "half", "ff"
    Text: viz_duration * 0.995, "right", 0.75, "half", "f"
    Text: viz_duration * 0.995, "right", 0.55, "half", "mf"
    Text: viz_duration * 0.995, "right", 0.40, "half", "mp"
    Text: viz_duration * 0.995, "right", 0.25, "half", "p"
    Text: viz_duration * 0.995, "right", 0.08, "half", "pp"
    
    Colour: "Black"
    Line width: 0.5
    Draw inner box
    
    Font size: 7
    Select outer viewport: 0, 0.8, dyn_top, dyn_bot
    Axes: 0, 1, 0, 1
    Colour: "{0.5, 0.35, 0.6}"
    Text: 0.95, "right", 0.5, "half", "Dynamics"
endif

# --- BEAT GRID / METRICAL STRUCTURE ---
# v2.9: shift further down if claves rendered (now 4 layers above us)
if extract_dynamics
    if render_claves
        viz_bottom = 6.2
        viz_top = 6.8
    else
        viz_bottom = 5.3
        viz_top = 5.9
    endif
else
    if render_claves
        viz_bottom = 5.3
        viz_top = 5.9
    else
        viz_bottom = 4.4
        viz_top = 5.0
    endif
endif

Select outer viewport: 0, 8, viz_bottom, viz_top
Select inner viewport: 0.8, 7.8, viz_bottom + 0.1, viz_top - 0.1

Axes: 0, viz_duration, 0, 1

# Beat markers at the written denominator. In compound metre, every third
# subdivision is shown as an intermediate pulse.
beat_time = 0
beat_num = 1
while beat_time < viz_duration
    beat_in_measure = ((beat_num - 1) mod time_sig_beats) + 1

    if beat_in_measure = 1
        Paint rectangle: "{0.4, 0.6, 0.8}", beat_time - 0.015, beat_time + 0.015, 0.1, 0.9
    elsif compound_meter and ((beat_in_measure - 1) mod 3 = 0)
        Paint rectangle: "{0.58, 0.70, 0.86}", beat_time - 0.011, beat_time + 0.011, 0.18, 0.82
    else
        Paint rectangle: "{0.76, 0.83, 0.92}", beat_time - 0.007, beat_time + 0.007, 0.30, 0.70
    endif

    beat_time = beat_time + notated_beat_dur
    beat_num = beat_num + 1
endwhile

Colour: "Black"
Line width: 0.5
Draw inner box

Font size: 7
Select outer viewport: 0, 0.8, viz_bottom, viz_top
Axes: 0, 1, 0, 1
Colour: "{0.4, 0.5, 0.7}"
Text: 0.95, "right", 0.5, "half", "Beats"

# --- LEGEND ---
# v2.9: legend top depends on whether claves and dynamics panels are present
if extract_dynamics
    if render_claves
        legend_top = 6.9
    else
        legend_top = 6.0
    endif
else
    if render_claves
        legend_top = 6.0
    else
        legend_top = 5.1
    endif
endif

Select outer viewport: 0, 8, legend_top, legend_top + 0.8
Axes: 0, 1, 0, 1

Font size: 6

# Note value legend
Paint rectangle: "{0.3, 0.5, 0.8}", 0.02, 0.05, 0.55, 0.85
Colour: "Black"
Text: 0.06, "left", 0.7, "half", "Whole"

Paint rectangle: "{0.4, 0.6, 0.75}", 0.14, 0.17, 0.55, 0.85
Text: 0.18, "left", 0.7, "half", "Half"

Paint rectangle: "{0.5, 0.7, 0.6}", 0.25, 0.28, 0.55, 0.85
Text: 0.29, "left", 0.7, "half", "Quarter"

Paint rectangle: "{0.7, 0.65, 0.5}", 0.38, 0.41, 0.55, 0.85
Text: 0.42, "left", 0.7, "half", "8th"

Paint rectangle: "{0.8, 0.55, 0.45}", 0.49, 0.52, 0.55, 0.85
Text: 0.53, "left", 0.7, "half", "16th"

Paint rectangle: "{0.85, 0.45, 0.4}", 0.60, 0.63, 0.55, 0.85
Text: 0.64, "left", 0.7, "half", "32nd"

# Rest indicator
Colour: "{0.8, 0.8, 0.85}"
Draw rectangle: 0.73, 0.76, 0.55, 0.85
Draw line: 0.73, 0.55, 0.76, 0.85
Colour: "Black"
Text: 0.77, "left", 0.7, "half", "Rest"

# Info
Font size: 5
Colour: "{0.4, 0.4, 0.5}"
Text: 0.02, "left", 0.25, "half", "Tempo: " + string$(tempo) + " BPM"
if auto_tempo
    Text: 0.18, "left", 0.25, "half", "(auto, " + fixed$(tempo_confidence * 100, 0) + "% conf)"
endif
Text: 0.38, "left", 0.25, "half", "Meter: " + string$(time_sig_beats) + "/" + string$(time_sig_type)
if compound_meter
    Text: 0.52, "left", 0.25, "half", "(compound)"
endif
Text: 0.65, "left", 0.25, "half", "Divisions: " + string$(divisions) + "/quarter"
Text: 0.82, "left", 0.25, "half", "Dotted: " + if allow_dotted then "yes" else "no" fi

# --- TIME AXIS ---
Select outer viewport: 0, 8, legend_top + 0.8, legend_top + 1.1
Select inner viewport: 0.8, 7.8, legend_top + 0.85, legend_top + 1.05

Axes: 0, viz_duration, 0, 1

Colour: "{0.3, 0.3, 0.4}"
Line width: 1
Draw line: 0, 0.7, viz_duration, 0.7

Font size: 5
tickStep = 1
if viz_duration > 10
    tickStep = 2
endif
if viz_duration > 20
    tickStep = 5
endif

t = 0
while t <= viz_duration
    Draw line: t, 0.7, t, 0.3
    Text: t, "centre", 0.1, "half", string$(t)
    t = t + tickStep
endwhile

Font size: 6
Text: viz_duration / 2, "centre", -0.5, "half", "Time (s)"

Font size: 10
Line width: 1
Colour: "Black"

appendInfoLine: "  Visualization complete"

# ===== CLEANUP =====
removeObject: intensity, textgrid
if detection_method = 2
    removeObject: spg_matrix, spectrogram
endif
if analysis_is_copy
    removeObject: analysis_sound
endif

# ===== OUTPUT =====
musicxml_saved = 0
musicxml_path$ = ""
if save_musicxml
    musicxml_path$ = chooseWriteFile$: "Save MusicXML as", "Speech_Rhythm.musicxml"
    if musicxml_path$ <> ""
        lower_path$ = lowerCase$(musicxml_path$)
        if not endsWith(lower_path$, ".musicxml") and not endsWith(lower_path$, ".xml")
            musicxml_path$ = musicxml_path$ + ".musicxml"
        endif
        writeFile: musicxml_path$, xml$
        musicxml_saved = 1
    endif
endif

writeInfoLine: xml$

appendInfoLine: ""
appendInfoLine: "===== ANALYSIS SUMMARY ====="
appendInfoLine: "Source: " + sound_name$
appendInfoLine: "Duration: " + fixed$(duration, 3) + " s"
appendInfoLine: "Onsets detected: " + string$(onset_count)
appendInfoLine: "Quantized onsets: " + string$(rhythm_onset_count)
appendInfoLine: "Notes/rests generated: " + string$(note_list_count)
if n_channels > 1
    appendInfoLine: "Analysis channel: " + string$(analysis_channel) + " of " + string$(n_channels) + " (strongest RMS)"
endif
if onset_overflow
    appendInfoLine: "WARNING: onset detector reached its safety cap of " + string$(max_onsets) + "."
endif
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
if divisions_adjusted
    appendInfoLine: "Grid adjusted to a multiple of 8 for exact 32nd-note durations."
endif
rest_count = 0
rest_divs_total = 0
for n from 1 to note_list_count
    if note_type[n] = 0
        rest_count = rest_count + 1
        rest_divs_total = rest_divs_total + note_duration[n]
    endif
endfor
appendInfoLine: "Rests generated: " + string$(rest_count) + " (" + fixed$(rest_divs_total * division_dur, 3) + " s quantized)"
if onset_count > rhythm_onset_count
    appendInfoLine: "Merged grid collisions: " + string$(onset_count - rhythm_onset_count)
endif
if detection_method = 2
    appendInfoLine: "Spectral-flux threshold: " + fixed$(flux_threshold, 5)
endif

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

if musicxml_saved
    appendInfoLine: ""
    appendInfoLine: "MusicXML saved: " + musicxml_path$
endif

appendInfoLine: ""
appendInfoLine: "=== USAGE ==="
if musicxml_saved
    appendInfoLine: "Open the saved MusicXML file in your notation software."
else
    appendInfoLine: "MusicXML was not saved; copy the XML output above if needed."
endif

# Leave the source and generated verification objects selected.
selectObject: sound
if create_textgrid_output
    plusObject: tg_rhythm
endif
if render_claves
    plusObject: claves_sound
endif

# =====================================================================
# PROCEDURES
# =====================================================================

procedure addToNoteList: .is_note, .dur_divs, .time, .dynamics
    .piece_index = 0
    while .dur_divs > 0
        if note_list_count >= max_notes
            note_overflow = 1
            .dur_divs = 0
        else
            @getBestNoteValue: .dur_divs
            .piece_index = .piece_index + 1
            .remaining_after = .dur_divs - getBestNoteValue.duration

            note_list_count = note_list_count + 1
            note_type[note_list_count] = .is_note
            note_duration[note_list_count] = getBestNoteValue.duration
            note_dotted[note_list_count] = getBestNoteValue.dotted
            note_time[note_list_count] = .time
            note_dynamics[note_list_count] = .dynamics
            note_value_type$[note_list_count] = getBestNoteValue.type$

            if .is_note
                note_tie_prev[note_list_count] = (.piece_index > 1)
                note_tie_next[note_list_count] = (.remaining_after > 0)
                note_show_dynamic[note_list_count] = (.piece_index = 1)
            else
                note_tie_prev[note_list_count] = 0
                note_tie_next[note_list_count] = 0
                note_show_dynamic[note_list_count] = 0
            endif

            .dur_divs = .remaining_after
            .time = .time + getBestNoteValue.duration * division_dur
        endif
    endwhile
endproc

procedure estimateTempo
    # Ignore long pauses and implausibly short gaps. Silence remains represented
    # in the score as rests; it should not dominate pulse estimation.
    n_iois = 0
    for i from 1 to onset_count - 1
        d = onset_time[i + 1] - onset_time[i]
        if d >= 0.05 and d <= 2.0
            n_iois = n_iois + 1
            ioi[n_iois] = d
        endif
    endfor

    if n_iois < 1
        n_iois = 1
        ioi[1] = max(0.05, min(2.0, onset_time[2] - onset_time[1]))
    endif

    hist_min = 0.05
    hist_max = 2.0
    n_bins = 78
    bin_width = (hist_max - hist_min) / n_bins

    for b from 1 to n_bins
        hist_count[b] = 0
        hist_center[b] = hist_min + (b - 0.5) * bin_width
    endfor

    for i from 1 to n_iois
        bin_idx = floor((ioi[i] - hist_min) / bin_width) + 1
        if bin_idx >= 1 and bin_idx <= n_bins
            hist_count[bin_idx] = hist_count[bin_idx] + 1
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

    weight_sum = 0
    weighted_ioi = 0
    for b from max(1, peak_bin - 2) to min(n_bins, peak_bin + 2)
        weight_sum = weight_sum + hist_count[b]
        weighted_ioi = weighted_ioi + hist_count[b] * hist_center[b]
    endfor

    if weight_sum > 0
        .dominant_ioi = weighted_ioi / weight_sum
    else
        .dominant_ioi = hist_center[peak_bin]
    endif

    peak_region_count = 0
    for b from max(1, peak_bin - 2) to min(n_bins, peak_bin + 2)
        peak_region_count = peak_region_count + hist_count[b]
    endfor
    .confidence = peak_region_count / n_iois

    # Map the detected IOI to the user-selected musical pulse.
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
    while raw_tempo < 40
        raw_tempo = raw_tempo * 2
    endwhile
    while raw_tempo > 240
        raw_tempo = raw_tempo / 2
    endwhile

    .tempo = round(raw_tempo)
    .tempo = max(30, min(300, .tempo))
endproc

procedure estimateMeter
    .beats = 4
    .beat_type = 4
    .compound = 0

    # This remains a heuristic: speech does not imply a unique metre.
    # Accents are compared in time (quarter-note units), not onset indices.
    if onset_count >= 4
        int_sum = 0
        for i from 1 to onset_count
            int_sum = int_sum + onset_intensity[i]
        endfor
        int_mean = int_sum / onset_count
        accent_threshold = int_mean + 3.0

        accent_count = 0
        last_accent_time = undefined
        count_2 = 0
        count_3 = 0
        count_4 = 0
        quarter_est = 60.0 / tempo

        for i from 1 to onset_count
            if onset_intensity[i] >= accent_threshold
                if last_accent_time <> undefined
                    step_count = round((onset_time[i] - last_accent_time) / quarter_est)
                    if step_count = 2
                        count_2 = count_2 + 1
                    elsif step_count = 3
                        count_3 = count_3 + 1
                    elsif step_count = 4
                        count_4 = count_4 + 1
                    endif
                    accent_count = accent_count + 1
                endif
                last_accent_time = onset_time[i]
            endif
        endfor

        if accent_count >= 2
            if count_3 > count_4 and count_3 > count_2
                # If the dominant IOI was mapped to an eighth-note pulse,
                # a 3-quarter measure is more plausibly grouped as 6/8.
                if pulse_unit = 4
                    .beats = 6
                    .beat_type = 8
                    .compound = 1
                else
                    .beats = 3
                    .beat_type = 4
                endif
            elsif count_2 > count_4
                .beats = 2
                .beat_type = 4
            else
                .beats = 4
                .beat_type = 4
            endif
        endif
    endif
endproc

procedure emitXMLElement: .type$, .dur_divs, .dynamics, .tie_prev, .tie_next, .show_dynamic
    .first_piece = 1
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
        .remaining_after = .dur_divs - write_dur

        .has_prev_tie = 0
        .has_next_tie = 0
        if .type$ <> "rest"
            if .tie_prev or .first_piece = 0
                .has_prev_tie = 1
            endif
            if .tie_next or .remaining_after > 0
                .has_next_tie = 1
            endif
        endif

        xml$ = xml$ + "      <note>" + newline$

        if .type$ = "rest"
            xml$ = xml$ + "        <rest/>" + newline$
        else
            if output_unpitched
                xml$ = xml$ + "        <unpitched>" + newline$
                xml$ = xml$ + "          <display-step>" + pitch_step$ + "</display-step>" + newline$
                xml$ = xml$ + "          <display-octave>" + string$(pitch_octave) + "</display-octave>" + newline$
                xml$ = xml$ + "        </unpitched>" + newline$
            else
                xml$ = xml$ + "        <pitch>" + newline$
                xml$ = xml$ + "          <step>" + pitch_step$ + "</step>" + newline$
                xml$ = xml$ + "          <octave>" + string$(pitch_octave) + "</octave>" + newline$
                xml$ = xml$ + "        </pitch>" + newline$
            endif
            if .has_prev_tie
                xml$ = xml$ + "        <tie type=""stop""/>" + newline$
            endif
            if .has_next_tie
                xml$ = xml$ + "        <tie type=""start""/>" + newline$
            endif
        endif

        xml$ = xml$ + "        <duration>" + string$(write_dur) + "</duration>" + newline$
        xml$ = xml$ + "        <type>" + local_note_type$ + "</type>" + newline$

        if is_dotted
            xml$ = xml$ + "        <dot/>" + newline$
        endif

        .write_dynamic = (.type$ <> "rest" and extract_dynamics and .show_dynamic and .first_piece)
        if .has_prev_tie or .has_next_tie or .write_dynamic
            xml$ = xml$ + "        <notations>" + newline$
            if .has_prev_tie
                xml$ = xml$ + "          <tied type=""stop""/>" + newline$
            endif
            if .has_next_tie
                xml$ = xml$ + "          <tied type=""start""/>" + newline$
            endif
            if .write_dynamic
                @getDynamicMarking: .dynamics
                if getDynamicMarking.marking$ <> ""
                    xml$ = xml$ + "          <dynamics>" + newline$
                    xml$ = xml$ + "            <" + getDynamicMarking.marking$ + "/>" + newline$
                    xml$ = xml$ + "          </dynamics>" + newline$
                endif
            endif
            xml$ = xml$ + "        </notations>" + newline$
        endif

        xml$ = xml$ + "      </note>" + newline$

        measure_position = measure_position + write_dur
        .dur_divs = .remaining_after
        .first_piece = 0
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

    # Tiers 1-2: quantized rhythm events and onset dynamics.
    tg_current_rel = 0
    for n from 1 to note_list_count
        note_dur_sec = note_duration[n] * division_dur
        end_rel = min(duration, tg_current_rel + note_dur_sec)

        if tg_current_rel < end_rel
            start_abs = sound_tmin + tg_current_rel
            end_abs = sound_tmin + end_rel
            probe_abs = min(sound_tmax - 1e-9, start_abs + 0.0001)

            selectObject: tg_rhythm

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

            if end_abs < sound_tmax
                nocheck Insert boundary: 1, end_abs
                nocheck Insert boundary: 2, end_abs
            endif
            interval_num1 = Get interval at time: 1, probe_abs
            nocheck Set interval text: 1, interval_num1, label$

            if note_type[n] = 1 and extract_dynamics and note_show_dynamic[n]
                @getDynamicMarking: note_dynamics[n]
                dyn_label$ = getDynamicMarking.marking$
            else
                dyn_label$ = ""
            endif
            interval_num2 = Get interval at time: 2, probe_abs
            nocheck Set interval text: 2, interval_num2, dyn_label$
        endif

        tg_current_rel = end_rel
    endfor

    # Tier 3: written beat grid, independent of note boundaries.
    beat_rel = 0
    beat_index = 1
    while beat_rel < duration
        next_beat_rel = min(duration, beat_rel + notated_beat_dur)
        start_abs = sound_tmin + beat_rel
        end_abs = sound_tmin + next_beat_rel
        probe_abs = min(sound_tmax - 1e-9, start_abs + 0.0001)

        selectObject: tg_rhythm
        if end_abs < sound_tmax
            nocheck Insert boundary: 3, end_abs
        endif
        interval_num3 = Get interval at time: 3, probe_abs
        beat_in_measure = ((beat_index - 1) mod time_sig_beats) + 1
        nocheck Set interval text: 3, interval_num3, string$(beat_in_measure)

        beat_rel = next_beat_rel
        beat_index = beat_index + 1
    endwhile

    # Tier 4: measure grid, independent of note boundaries.
    measure_rel = 0
    tg_measure_num = 1
    while measure_rel < duration
        next_measure_rel = min(duration, measure_rel + measure_dur)
        start_abs = sound_tmin + measure_rel
        end_abs = sound_tmin + next_measure_rel
        probe_abs = min(sound_tmax - 1e-9, start_abs + 0.0001)

        selectObject: tg_rhythm
        if end_abs < sound_tmax
            nocheck Insert boundary: 4, end_abs
        endif
        interval_num4 = Get interval at time: 4, probe_abs
        nocheck Set interval text: 4, interval_num4, "M" + string$(tg_measure_num)

        measure_rel = next_measure_rel
        tg_measure_num = tg_measure_num + 1
    endwhile

    selectObject: tg_rhythm
    Rename: sound_name$ + "_rhythm"
endproc
