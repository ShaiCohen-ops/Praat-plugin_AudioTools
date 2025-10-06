# ============================================================
# Praat AudioTools - Time-based jitter-shimmer to formant mapping.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Filtering or timbral modification script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# Time-based jitter/shimmer to formant mapping script

clearinfo
appendInfoLine: "=== TIME-BASED JITTER/SHIMMER TO FORMANT MAPPING ==="

if not selected("Sound")
    exitScript: "Please select Sound objects first."
endif

number_of_selected_sounds = numberOfSelected("Sound")
appendInfoLine: "Number of sounds selected: ", number_of_selected_sounds

for i from 1 to number_of_selected_sounds
    sound'i' = selected("Sound", i)
endfor

for current_sound from 1 to number_of_selected_sounds
    select sound'current_sound'
    originalName$ = selected$("Sound")
    duration = Get total duration

    # Analysis settings
    num_windows = 6
    window_size = 0.2
    analysis_times# = zero#(num_windows)
    jitter_values# = zero#(num_windows)
    shimmer_values# = zero#(num_windows)

    # Analyze each window
    for window from 1 to num_windows
        analysis_time = (window - 1) * (duration - window_size) / (num_windows - 1)
        if analysis_time < 0.1
            analysis_time = 0.1
        endif
        if analysis_time > duration - window_size - 0.1
            analysis_time = duration - window_size - 0.1
        endif

        analysis_times#[window] = analysis_time
        window_start = analysis_time
        window_end = analysis_time + window_size

        select sound'current_sound'
        window_sound = Extract part: window_start, window_end, "Hamming", 1, "no"

        select window_sound
        To Pitch (cc): 0, 75, 15, "no", 0.03, 0.45, 0.01, 0.35, 0.14, 600
        pitch = selected("Pitch")
        
        select window_sound
        plus pitch
        To PointProcess (cc)
        pointprocess = selected("PointProcess")

        select pointprocess
        numPulses = Get number of points

        if numPulses < 3
            jitter_values#[window] = 0.5
            shimmer_values#[window] = 3.0
        else
            select window_sound
            plus pitch
            plus pointprocess
            voiceReport$ = Voice report: 0, 0, 75, 600, 1.3, 1.6, 0.03, 0.45

            jitter_values#[window] = extractNumber(extractLine$(voiceReport$, "Jitter (local)"), "")
            shimmer_values#[window] = extractNumber(extractLine$(voiceReport$, "Shimmer (local)"), "")

            if jitter_values#[window] = undefined
                jitter_values#[window] = 0.5
            endif
            if shimmer_values#[window] = undefined
                shimmer_values#[window] = 3.0
            endif
        endif

        select window_sound
        plus pitch
        plus pointprocess
        Remove
    endfor

    # Process segments
    select sound'current_sound'
    finalSound = Copy: "temp_base"

    for window from 1 to num_windows
        if window = 1
            segment_start = 0
        else
            segment_start = (analysis_times#[window-1] + analysis_times#[window]) / 2
        endif

        if window = num_windows
            segment_end = duration
        else
            segment_end = (analysis_times#[window] + analysis_times#[window+1]) / 2
        endif

        select sound'current_sound'
        segment_sound = Extract part: segment_start, segment_end, "Rectangular", 1, "no"

        # Filter settings based on jitter/shimmer (convert from % to ratio)
        f1_shift = 1.0 + (jitter_values#[window] / 100 * 0.1)
        f2_shift = 1.0 + (shimmer_values#[window] / 100 * 0.08)
        
        select segment_sound
        f1_filtered = Filter (pass Hann band): 300 * f1_shift, 900 * f1_shift, 100
        
        select segment_sound
        f2_filtered = Filter (pass Hann band): 900 * f2_shift, 2500 * f2_shift, 100

        select f1_filtered
        plus f2_filtered
        Combine to stereo
        segment_final = selected("Sound")
        
        select segment_final
        Convert to mono
        segment_mono = selected("Sound")

        if window = 1
            select segment_mono
            finalSound = Copy: "time_formant_mod_" + originalName$
        else
            select finalSound
            plus segment_mono
            Concatenate
            temp = selected("Sound")
            select finalSound
            Remove
            select temp
            Rename: "time_formant_mod_" + originalName$
            finalSound = selected("Sound")
        endif

        # Cleanup
        select segment_sound
        plus f1_filtered
        plus f2_filtered
        plus segment_final
        plus segment_mono
        Remove
    endfor

    select finalSound
    Scale peak: 0.99
endfor

# Helper procedures
procedure extractLine$ (.report$, .key$)
    line$ = ""
    for i from 1 to numberOfLines(.report$)
        if index(line$(.report$, i), .key$) > 0
            line$ = line$(.report$, i)
        endif
    endfor
    .extractLine$ = line$
endproc

procedure extractNumber (.line$, .after$)
    number = undefined
    if length(.line$) > 0
        p = index(.line$, ":")
        if p > 0
            value$ = trim$(mid$(.line$, p + 1))
            value$ = replace$(value$, "%", "")
            value$ = replace$(value$, "seconds", "")
            value$ = replace$(value$, .after$, "")
            number = number$(value$)
        endif
    endif
    .extractNumber = number
endproc
Play