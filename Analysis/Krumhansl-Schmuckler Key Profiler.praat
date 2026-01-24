# ============================================================
# Praat AudioTools - Krumhansl-Schmuckler Key Profiler.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Detects musical key using the Krumhansl-Schmuckler key-finding
#   algorithm. Analyzes spectral content, bins to pitch classes,
#   and correlates with cognitive key profiles from music psychology.
#   Supports multiple profile sets (K-S, Temperley, Albrecht-Shanahan).
#
# Changelog v0.4:
#   - Fixed == to = for Praat compatibility
#   - Added alternative key profiles (Temperley, Albrecht-Shanahan)
#   - Added output Table with all correlations
#   - Added presets for different music types
#   - Matched visualization style to other AudioTools scripts
#
# Usage:
#   Select a Sound object and run this script.
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original_sound = selected("Sound")
original_name$ = selected$("Sound")

form Key Detection (Krumhansl-Schmuckler)
    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Classical/Orchestral
        option Pop/Rock
        option Jazz
        option Solo Instrument
        option Voice/Choir
    comment === Key Profile ===
    optionmenu Profile_type: 1
        option Krumhansl-Schmuckler (original)
        option Temperley (CBMS)
        option Albrecht-Shanahan (2013)
    comment === Analysis Parameters ===
    positive Min_frequency_Hz 60
    positive Max_frequency_Hz 1500
    positive Harmonic_tolerance_cents 50
    boolean Remove_harmonic_duplicates 1
    comment === Window Settings ===
    real Window_size_seconds 0.5
    real Time_step_seconds 0.25
    positive Max_peaks_per_frame 8
    comment === Speed Optimization ===
    boolean Use_downsampling 1
    positive Target_sample_rate_Hz 8000
    comment === Output ===
    boolean Show_visualization 1
    boolean Create_output_table 1
    real Minimum_confidence_threshold 0.2
endform

# === APPLY PRESETS ===
if preset = 2
    # Classical/Orchestral
    min_frequency_Hz = 50
    max_frequency_Hz = 2000
    window_size_seconds = 1.0
    time_step_seconds = 0.5
    max_peaks_per_frame = 12
    harmonic_tolerance_cents = 40
    presetName$ = "Classical"
elsif preset = 3
    # Pop/Rock
    min_frequency_Hz = 80
    max_frequency_Hz = 1200
    window_size_seconds = 0.5
    time_step_seconds = 0.25
    max_peaks_per_frame = 8
    harmonic_tolerance_cents = 50
    presetName$ = "PopRock"
elsif preset = 4
    # Jazz
    min_frequency_Hz = 60
    max_frequency_Hz = 1500
    window_size_seconds = 0.75
    time_step_seconds = 0.25
    max_peaks_per_frame = 10
    harmonic_tolerance_cents = 60
    presetName$ = "Jazz"
elsif preset = 5
    # Solo Instrument
    min_frequency_Hz = 80
    max_frequency_Hz = 2000
    window_size_seconds = 0.25
    time_step_seconds = 0.1
    max_peaks_per_frame = 6
    harmonic_tolerance_cents = 30
    presetName$ = "SoloInstrument"
elsif preset = 6
    # Voice/Choir
    min_frequency_Hz = 80
    max_frequency_Hz = 1000
    window_size_seconds = 0.5
    time_step_seconds = 0.25
    max_peaks_per_frame = 8
    harmonic_tolerance_cents = 50
    presetName$ = "Voice"
else
    presetName$ = "Custom"
endif

# === KEY PROFILES ===
# Krumhansl-Schmuckler (1990)
ks_maj# = {6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88}
ks_min# = {6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17}

# Temperley CBMS (2007)
temp_maj# = {5.0, 2.0, 3.5, 2.0, 4.5, 4.0, 2.0, 4.5, 2.0, 3.5, 1.5, 4.0}
temp_min# = {5.0, 2.0, 3.5, 4.5, 2.0, 4.0, 2.0, 4.5, 3.5, 2.0, 1.5, 4.0}

# Albrecht-Shanahan (2013)
as_maj# = {0.238, 0.006, 0.111, 0.006, 0.137, 0.094, 0.016, 0.214, 0.009, 0.080, 0.008, 0.081}
as_min# = {0.220, 0.006, 0.104, 0.123, 0.019, 0.103, 0.012, 0.214, 0.062, 0.022, 0.061, 0.052}

# Select profile
if profile_type = 1
    profile_maj# = ks_maj#
    profile_min# = ks_min#
    profileName$ = "Krumhansl-Schmuckler"
elsif profile_type = 2
    profile_maj# = temp_maj#
    profile_min# = temp_min#
    profileName$ = "Temperley"
else
    profile_maj# = as_maj#
    profile_min# = as_min#
    profileName$ = "Albrecht-Shanahan"
endif

# Initialize Global Chroma Bin
for i from 0 to 11
    global_chroma[i] = 0
endfor

selectObject: original_sound
original_sr = Get sampling frequency
duration = Get total duration

writeInfoLine: "=== Krumhansl-Schmuckler Key Profiler v0.4 ==="
appendInfoLine: "File: ", original_name$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Profile: ", profileName$
appendInfoLine: "Duration: ", fixed$(duration, 2), " seconds"
appendInfoLine: ""

if use_downsampling and original_sr > target_sample_rate_Hz
    selectObject: original_sound
    sound = Resample: target_sample_rate_Hz, 50
    appendInfoLine: "Resampled to ", target_sample_rate_Hz, " Hz for speed"
else
    selectObject: original_sound
    sound = Copy: "analysis_copy"
endif

if window_size_seconds > duration
    selectObject: sound
    Remove
    exitScript: "Window size (" + fixed$(window_size_seconds, 2) + "s) is longer than audio duration (" + fixed$(duration, 2) + "s)"
endif

if window_size_seconds < 0.05
    appendInfoLine: "Warning: Very short window size may produce unreliable results"
endif

frame_count = 0
t = 0
appendInfoLine: "Window size: ", window_size_seconds, "s, Step: ", time_step_seconds, "s"
appendInfoLine: ""

total_frames = floor((duration - window_size_seconds) / time_step_seconds)

while t <= (duration - window_size_seconds)
    frame_count += 1
    
    if frame_count mod 10 = 0
        appendInfoLine: "Processing frame ", frame_count, "/", total_frames
    endif
    
    selectObject: sound
    extract = Extract part: t, t + window_size_seconds, "Hanning", 1.0, "no"
    spectrum = To Spectrum: "yes"
    
    selectObject: spectrum
    n_bins = Get number of bins
    n_peaks = 0
    
    for i from 2 to n_bins - 1
        freq = Get frequency from bin number: i
        
        if freq > max_frequency_Hz
            goto END_PEAK_SEARCH
        endif

        if freq >= min_frequency_Hz
            re = Get real value in bin: i
            im = Get imaginary value in bin: i
            power = sqrt(re^2 + im^2)
            
            re_prev = Get real value in bin: i - 1
            im_prev = Get imaginary value in bin: i - 1
            power_prev = sqrt(re_prev^2 + im_prev^2)
            
            re_next = Get real value in bin: i + 1
            im_next = Get imaginary value in bin: i + 1
            power_next = sqrt(re_next^2 + im_next^2)
            
            if power > power_prev and power > power_next and power > 0.0001
                n_peaks += 1
                peak_freq[n_peaks] = freq
                peak_power[n_peaks] = power
            endif
        endif
    endfor
    
    label END_PEAK_SEARCH

    if n_peaks > max_peaks_per_frame
        for i from 1 to max_peaks_per_frame
            max_idx = i
            for j from i + 1 to n_peaks
                if peak_power[j] > peak_power[max_idx]
                    max_idx = j
                endif
            endfor
            if max_idx <> i
                temp_p = peak_power[i]
                temp_f = peak_freq[i]
                peak_power[i] = peak_power[max_idx]
                peak_freq[i] = peak_freq[max_idx]
                peak_power[max_idx] = temp_p
                peak_freq[max_idx] = temp_f
            endif
        endfor
        n_peaks = max_peaks_per_frame
    endif

    if remove_harmonic_duplicates and n_peaks > 1
        for i from 1 to n_peaks
            keep[i] = 1
        endfor
        
        for i from 1 to n_peaks
            if keep[i] = 1
                for j from 1 to n_peaks
                    if i <> j and keep[j] = 1 and peak_power[j] > peak_power[i]
                        ratio = peak_freq[i] / peak_freq[j]
                        nearest_harmonic = round(ratio)
                        
                        if nearest_harmonic >= 2
                            cents_deviation = abs(1200 * log2(ratio / nearest_harmonic))
                            
                            if cents_deviation < harmonic_tolerance_cents
                                keep[i] = 0
                                goto NEXT_PEAK
                            endif
                        endif
                    endif
                endfor
                label NEXT_PEAK
            endif
        endfor
    else
        for i from 1 to n_peaks
            keep[i] = 1
        endfor
    endif

    frame_total = 0
    for i from 1 to n_peaks
        if keep[i] = 1
            frame_total += peak_power[i]
        endif
    endfor
    
    if frame_total > 0
        for i from 1 to n_peaks
            if keep[i] = 1
                midi = 69 + 12 * log2(peak_freq[i] / 440)
                pitch_class = round(midi) mod 12
                if pitch_class < 0
                    pitch_class += 12
                endif
                normalized_power = peak_power[i] / frame_total
                global_chroma[pitch_class] += normalized_power
            endif
        endfor
    endif

    selectObject: extract, spectrum
    Remove
    
    t += time_step_seconds
endwhile

selectObject: sound
Remove

appendInfoLine: ""
appendInfoLine: "Analyzed ", frame_count, " frames"
appendInfoLine: ""

total_chroma = 0
for i from 0 to 11
    total_chroma += global_chroma[i]
endfor

if total_chroma = 0
    exitScript: "No spectral peaks found. Try different frequency range or check audio content."
endif

for i from 0 to 11
    global_chroma[i] = global_chroma[i] / total_chroma
endfor

for i from 0 to 23
    all_correlations[i] = -2
    all_keys$[i] = ""
endfor

result_index = 0

for root from 0 to 11
    sum_x = 0
    sum_y = 0
    sum_xy = 0
    sum_x2 = 0
    sum_y2 = 0
    n = 12
    
    for i from 0 to 11
        idx = (root + i) mod 12
        val_audio = global_chroma[idx]
        val_profile = profile_maj#[i + 1]
        
        sum_x += val_audio
        sum_y += val_profile
        sum_xy += val_audio * val_profile
        sum_x2 += val_audio^2
        sum_y2 += val_profile^2
    endfor
    
    denominator_x = n * sum_x2 - sum_x^2
    denominator_y = n * sum_y2 - sum_y^2
    
    if denominator_x > 0 and denominator_y > 0
        r_maj = (n * sum_xy - sum_x * sum_y) / (sqrt(denominator_x) * sqrt(denominator_y))
    else
        r_maj = -1
    endif
    
    @numToNote: root
    all_correlations[result_index] = r_maj
    all_keys$[result_index] = numToNote.result$ + " Major"
    result_index += 1

    sum_x = 0
    sum_y = 0
    sum_xy = 0
    sum_x2 = 0
    sum_y2 = 0
    
    for i from 0 to 11
        idx = (root + i) mod 12
        val_audio = global_chroma[idx]
        val_profile = profile_min#[i + 1]
        
        sum_x += val_audio
        sum_y += val_profile
        sum_xy += val_audio * val_profile
        sum_x2 += val_audio^2
        sum_y2 += val_profile^2
    endfor
    
    denominator_x = n * sum_x2 - sum_x^2
    denominator_y = n * sum_y2 - sum_y^2
    
    if denominator_x > 0 and denominator_y > 0
        r_min = (n * sum_xy - sum_x * sum_y) / (sqrt(denominator_x) * sqrt(denominator_y))
    else
        r_min = -1
    endif
    
    @numToNote: root
    all_correlations[result_index] = r_min
    all_keys$[result_index] = numToNote.result$ + " Minor"
    result_index += 1
endfor

# Find best and second best
best_r = -2
best_key$ = "Unknown"
second_r = -2
second_key$ = ""

for i from 0 to 23
    if all_correlations[i] > best_r
        second_r = best_r
        second_key$ = best_key$
        best_r = all_correlations[i]
        best_key$ = all_keys$[i]
    elsif all_correlations[i] > second_r
        second_r = all_correlations[i]
        second_key$ = all_keys$[i]
    endif
endfor

max_chroma = 0.000001
for i from 0 to 11
    if global_chroma[i] > max_chroma
        max_chroma = global_chroma[i]
    endif
endfor

space_pos = index(best_key$, " ")
best_root$ = left$(best_key$, space_pos - 1)
best_mode$ = right$(best_key$, length(best_key$) - space_pos)

# === VISUALIZATION ===
if show_visualization
    Erase all
    
    # --- Title ---
    Select outer viewport: 0, 8, 0.0, 0.5
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Key Detection: " + best_key$ + " [" + profileName$ + "]"
    
    # --- Confidence (separate viewport below title) ---
    Select outer viewport: 0, 8, 0.45, 0.9
    Font size: 10
    if best_r < minimum_confidence_threshold
        confidence_text$ = "r = " + fixed$(best_r, 3) + " (LOW)"
        Colour: "{0.8, 0.3, 0.3}"
    elsif best_r < 0.5
        confidence_text$ = "r = " + fixed$(best_r, 3) + " (MODERATE)"
        Colour: "{0.7, 0.6, 0.2}"
    elsif best_r < 0.7
        confidence_text$ = "r = " + fixed$(best_r, 3) + " (GOOD)"
        Colour: "{0.4, 0.6, 0.3}"
    else
        confidence_text$ = "r = " + fixed$(best_r, 3) + " (VERY HIGH)"
        Colour: "{0.2, 0.7, 0.2}"
    endif
    Text: 0.5, "centre", 0.5, "half", confidence_text$
    
    # --- Chroma histogram (shift down to make room) ---
    Select outer viewport: 0, 8, 1.0, 3.0
    Select inner viewport: 0.5, 7.5, 1.1, 2.9
      
    Axes: -0.5, 11.5, 0, 1.1
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", -0.5, 11.5, 0, 1.1
    
    for i from 0 to 11
        val = global_chroma[i] / max_chroma
        @numToNote: i
        note_name$ = numToNote.result$
        
        if note_name$ = best_root$
            col$ = "{0.2, 0.7, 0.3}"
        else
            col$ = "{0.3, 0.5, 0.8}"
        endif
        
        Paint rectangle: col$, i - 0.35, i + 0.35, 0, val
        
        Colour: "Black"
        Font size: 8
        Text: i, "centre", -0.08, "top", note_name$
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Strength"
    Text bottom: "yes", "Pitch Class Distribution"
    
    # --- Correlation profile ---
    Select outer viewport: 0, 8, 3.0, 4.2
    Select inner viewport: 0.5, 7.5, 3.1, 4.1
    
    Axes: -0.5, 23.5, -0.3, 1.0
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", -0.5, 23.5, -0.3, 1.0
    
    # Zero line
    Colour: "{0.8, 0.8, 0.8}"
    Draw line: -0.5, 0, 23.5, 0
    
    for i from 0 to 23
        r = all_correlations[i]
        
        if all_keys$[i] = best_key$
            col$ = "{0.2, 0.7, 0.3}"
        elsif r > 0.3
            col$ = "{0.8, 0.5, 0.2}"
        else
            col$ = "{0.6, 0.6, 0.6}"
        endif
        
        Colour: col$
        Line width: 2
        Draw line: i, 0, i, r
        Paint circle: col$, i, r, 0.25
    endfor
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "r"
    Text bottom: "yes", "All 24 Keys (Major: 0-11, Minor: 12-23)"
    
    # --- Parameters ---
    Select outer viewport: 0, 8, 4.3, 4.6
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "2nd: " + second_key$ + " (r=" + fixed$(second_r, 3) + ") | Frames: " + string$(frame_count) + " | Preset: " + presetName$
    
    Font size: 10
    Colour: "Black"
endif

# === OUTPUT TABLE ===
if create_output_table
    table = Create Table with column names: "KeyProfile_" + original_name$, 24, "key correlation"
    
    # Restore correlations (they were modified for ranking)
    for root from 0 to 11
        @numToNote: root
        selectObject: table
        Set string value: root + 1, "key", numToNote.result$ + " Major"
        Set string value: root + 13, "key", numToNote.result$ + " Minor"
    endfor
    
    # Re-correlate to get fresh values for table
    for root from 0 to 11
        sum_x = 0
        sum_y = 0
        sum_xy = 0
        sum_x2 = 0
        sum_y2 = 0
        n = 12
        
        for i from 0 to 11
            idx = (root + i) mod 12
            val_audio = global_chroma[idx]
            val_profile = profile_maj#[i + 1]
            
            sum_x += val_audio
            sum_y += val_profile
            sum_xy += val_audio * val_profile
            sum_x2 += val_audio^2
            sum_y2 += val_profile^2
        endfor
        
        denominator_x = n * sum_x2 - sum_x^2
        denominator_y = n * sum_y2 - sum_y^2
        
        if denominator_x > 0 and denominator_y > 0
            r_maj = (n * sum_xy - sum_x * sum_y) / (sqrt(denominator_x) * sqrt(denominator_y))
        else
            r_maj = -1
        endif
        
        selectObject: table
        Set numeric value: root + 1, "correlation", r_maj
        
        # Minor
        sum_x = 0
        sum_y = 0
        sum_xy = 0
        sum_x2 = 0
        sum_y2 = 0
        
        for i from 0 to 11
            idx = (root + i) mod 12
            val_audio = global_chroma[idx]
            val_profile = profile_min#[i + 1]
            
            sum_x += val_audio
            sum_y += val_profile
            sum_xy += val_audio * val_profile
            sum_x2 += val_audio^2
            sum_y2 += val_profile^2
        endfor
        
        denominator_x = n * sum_x2 - sum_x^2
        denominator_y = n * sum_y2 - sum_y^2
        
        if denominator_x > 0 and denominator_y > 0
            r_min = (n * sum_xy - sum_x * sum_y) / (sqrt(denominator_x) * sqrt(denominator_y))
        else
            r_min = -1
        endif
        
        selectObject: table
        Set numeric value: root + 13, "correlation", r_min
    endfor
    
    appendInfoLine: "Created output Table: KeyProfile_", original_name$
endif

# === FINAL REPORT ===
appendInfoLine: ""
appendInfoLine: "==================================="
appendInfoLine: "DETECTED KEY: ", best_key$
appendInfoLine: "Correlation: ", fixed$(best_r, 4)
appendInfoLine: "Profile: ", profileName$
appendInfoLine: "==================================="
appendInfoLine: ""

if best_r < minimum_confidence_threshold
    appendInfoLine: "WARNING: Low confidence - music may be atonal, modulating, or ambiguous"
    appendInfoLine: ""
endif

appendInfoLine: "Top 5 key candidates:"

# Need to recalculate for ranking since we modified the array
rank_corr# = zero#(24)
for root from 0 to 11
    sum_x = 0
    sum_y = 0
    sum_xy = 0
    sum_x2 = 0
    sum_y2 = 0
    n = 12
    
    for i from 0 to 11
        idx = (root + i) mod 12
        val_audio = global_chroma[idx]
        val_profile = profile_maj#[i + 1]
        sum_x += val_audio
        sum_y += val_profile
        sum_xy += val_audio * val_profile
        sum_x2 += val_audio^2
        sum_y2 += val_profile^2
    endfor
    
    denominator_x = n * sum_x2 - sum_x^2
    denominator_y = n * sum_y2 - sum_y^2
    
    if denominator_x > 0 and denominator_y > 0
        rank_corr#[root + 1] = (n * sum_xy - sum_x * sum_y) / (sqrt(denominator_x) * sqrt(denominator_y))
    else
        rank_corr#[root + 1] = -1
    endif
    
    @numToNote: root
    rank_keys$[root + 1] = numToNote.result$ + " Major"
    
    sum_x = 0
    sum_y = 0
    sum_xy = 0
    sum_x2 = 0
    sum_y2 = 0
    
    for i from 0 to 11
        idx = (root + i) mod 12
        val_audio = global_chroma[idx]
        val_profile = profile_min#[i + 1]
        sum_x += val_audio
        sum_y += val_profile
        sum_xy += val_audio * val_profile
        sum_x2 += val_audio^2
        sum_y2 += val_profile^2
    endfor
    
    denominator_x = n * sum_x2 - sum_x^2
    denominator_y = n * sum_y2 - sum_y^2
    
    if denominator_x > 0 and denominator_y > 0
        rank_corr#[root + 13] = (n * sum_xy - sum_x * sum_y) / (sqrt(denominator_x) * sqrt(denominator_y))
    else
        rank_corr#[root + 13] = -1
    endif
    
    @numToNote: root
    rank_keys$[root + 13] = numToNote.result$ + " Minor"
endfor

for rank from 1 to 5
    max_r = -2
    max_idx = -1
    for i from 1 to 24
        if rank_corr#[i] > max_r
            max_r = rank_corr#[i]
            max_idx = i
        endif
    endfor
    if max_idx >= 1
        appendInfoLine: rank, ". ", rank_keys$[max_idx], " (r = ", fixed$(rank_corr#[max_idx], 3), ")"
        rank_corr#[max_idx] = -3
    endif
endfor

appendInfoLine: ""
appendInfoLine: "Done!"

selectObject: original_sound

procedure numToNote: .num
    if .num = 0
        .result$ = "C"
    elsif .num = 1
        .result$ = "C#"
    elsif .num = 2
        .result$ = "D"
    elsif .num = 3
        .result$ = "D#"
    elsif .num = 4
        .result$ = "E"
    elsif .num = 5
        .result$ = "F"
    elsif .num = 6
        .result$ = "F#"
    elsif .num = 7
        .result$ = "G"
    elsif .num = 8
        .result$ = "G#"
    elsif .num = 9
        .result$ = "A"
    elsif .num = 10
        .result$ = "A#"
    elsif .num = 11
        .result$ = "B"
    endif
endproc