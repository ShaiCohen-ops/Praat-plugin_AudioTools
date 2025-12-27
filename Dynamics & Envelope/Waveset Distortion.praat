# ============================================================
# Praat AudioTools - Waveset Distortion.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   True sample-level waveset distortion based on CDP concepts.
#   Wavesets are pseudo-wavecycles defined as segments between zero-crossings.
#   WARNING: This is slow for long files. Use Fast Waveset Distortion for speed.
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Waveset Distortion (Accurate)
    optionmenu Type 1
        option Repeat
        option Skip
        option Reverse
        option Stretch
        option Compress
        option Randomize
        option Amplitude
    positive Amount 2.0
    boolean Preserve_length 0
    comment === Performance ===
    positive Max_recommended_seconds 10
    boolean Show_progress 1
endform

# === VALIDATION ===
if numberOfSelected("Sound") = 0
    exitScript: "Please select a Sound object first."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")
original_duration = Get total duration
sampling_rate = Get sampling frequency
n_samples = Get number of samples

# === RUNTIME WARNING ===
estimated_time = n_samples / 10000 * 0.5
if type = 4
    estimated_time = estimated_time * amount
elsif type = 1
    estimated_time = estimated_time * amount
endif

writeInfoLine: "============================================"
appendInfoLine: "WAVESET DISTORTION (Accurate/Slow Version)"
appendInfoLine: "============================================"
appendInfoLine: ""
appendInfoLine: "Input: ", soundName$
appendInfoLine: "Duration: ", fixed$(original_duration, 2), " seconds"
appendInfoLine: "Samples: ", n_samples
appendInfoLine: ""
appendInfoLine: "Estimated processing time: ", fixed$(estimated_time, 1), " seconds"
appendInfoLine: ""

if original_duration > max_recommended_seconds
    appendInfoLine: "WARNING: File exceeds recommended length!"
    appendInfoLine: "Consider using 'Fast Waveset Distortion' for long files."
    appendInfoLine: ""
    
    beginPause: "Long File Warning"
        comment: "This file is " + fixed$(original_duration, 1) + " seconds long."
        comment: "Estimated processing time: " + fixed$(estimated_time, 0) + " seconds."
        comment: ""
        comment: "For faster processing, use 'Fast Waveset Distortion' instead."
        comment: ""
        comment: "Continue with accurate (slow) processing?"
    clicked = endPause: "Cancel", "Continue", 2, 1
    
    if clicked = 1
        selectObject: sound
        exitScript: "Cancelled by user."
    endif
endif

appendInfoLine: "Starting processing..."
appendInfoLine: ""

progress_interval = max(1, floor(n_samples / 20))
start_time = stopwatch

# === EXTRACT SAMPLES ===
if show_progress
    appendInfoLine: "[1/5] Extracting samples..."
endif

selectObject: sound
samples# = zero#(n_samples)

for i from 1 to n_samples
    samples#[i] = Get value at sample number: 1, i
    
    if show_progress and (i mod progress_interval = 0)
        appendInfo: "."
    endif
endfor

if show_progress
    appendInfoLine: " done"
endif

# === FIND ZERO CROSSINGS ===
if show_progress
    appendInfoLine: "[2/5] Finding zero crossings..."
endif

zero_crossings# = zero#(n_samples)
n_crossings = 0

for i from 2 to n_samples
    if (samples#[i-1] >= 0 and samples#[i] < 0) or (samples#[i-1] < 0 and samples#[i] >= 0)
        n_crossings += 1
        zero_crossings#[n_crossings] = i
    endif
endfor

if show_progress
    appendInfoLine: "   Found ", n_crossings, " zero crossings (", n_crossings - 1, " wavesets)"
endif

if n_crossings < 3
    exitScript: "Not enough zero crossings found for waveset processing."
endif

# === ALLOCATE OUTPUT ===
output_samples# = zero#(n_samples * 10)
output_index = 1

# === PROCESS WAVESETS ===
if show_progress
    appendInfoLine: "[3/5] Processing wavesets (", type$, ")..."
endif

n_wavesets = n_crossings - 1
ws_progress_interval = max(1, floor(n_wavesets / 20))

if type = 1
    # REPEAT wavesets
    for waveset from 1 to n_wavesets
        start_idx = zero_crossings#[waveset]
        end_idx = zero_crossings#[waveset + 1] - 1
        waveset_length = end_idx - start_idx + 1
        
        for sample from start_idx to end_idx
            if output_index <= size(output_samples#)
                output_samples#[output_index] = samples#[sample]
                output_index += 1
            endif
        endfor
        
        repetitions = round(amount) - 1
        for rep from 1 to repetitions
            decay_factor = 0.8^rep
            for sample from start_idx to end_idx
                if output_index <= size(output_samples#)
                    output_samples#[output_index] = samples#[sample] * decay_factor
                    output_index += 1
                endif
            endfor
        endfor
        
        if show_progress and (waveset mod ws_progress_interval = 0)
            appendInfo: "."
        endif
    endfor

elsif type = 2
    # SKIP wavesets
    skipped_count = 0
    for waveset from 1 to n_wavesets
        if randomUniform(0, 1) > (1/amount)
            start_idx = zero_crossings#[waveset]
            end_idx = zero_crossings#[waveset + 1] - 1
            
            for sample from start_idx to end_idx
                if output_index <= size(output_samples#)
                    output_samples#[output_index] = samples#[sample]
                    output_index += 1
                endif
            endfor
        else
            skipped_count += 1
        endif
        
        if show_progress and (waveset mod ws_progress_interval = 0)
            appendInfo: "."
        endif
    endfor
    appendInfoLine: ""
    appendInfoLine: "   Skipped ", skipped_count, " wavesets"

elsif type = 3
    # REVERSE each waveset individually
    # NOTE: Praat for-loops don't work descending, so we use ascending index math
    for waveset from 1 to n_wavesets
        start_idx = zero_crossings#[waveset]
        end_idx = zero_crossings#[waveset + 1] - 1
        waveset_length = end_idx - start_idx + 1
        
        # Write samples in reverse order using ascending loop
        for i from 1 to waveset_length
            reverse_sample_idx = end_idx - i + 1
            if output_index <= size(output_samples#)
                output_samples#[output_index] = samples#[reverse_sample_idx]
                output_index += 1
            endif
        endfor
        
        if show_progress and (waveset mod ws_progress_interval = 0)
            appendInfo: "."
        endif
    endfor

elsif type = 4
    # STRETCH wavesets
    for waveset from 1 to n_wavesets
        start_idx = zero_crossings#[waveset]
        end_idx = zero_crossings#[waveset + 1] - 1
        waveset_length = end_idx - start_idx + 1
        
        new_length = max(2, round(waveset_length * amount))
        
        for new_sample from 1 to new_length
            orig_pos_relative = (new_sample - 1) / (new_length - 1)
            exact_pos = start_idx + orig_pos_relative * (waveset_length - 1)
            idx1 = floor(exact_pos)
            idx2 = idx1 + 1
            frac = exact_pos - idx1
            
            if idx2 <= end_idx
                value = samples#[idx1] * (1 - frac) + samples#[idx2] * frac
            else
                value = samples#[idx1]
            endif
            
            if output_index <= size(output_samples#)
                output_samples#[output_index] = value
                output_index += 1
            endif
        endfor
        
        if show_progress and (waveset mod ws_progress_interval = 0)
            appendInfo: "."
        endif
    endfor

elsif type = 5
    # COMPRESS wavesets
    for waveset from 1 to n_wavesets
        start_idx = zero_crossings#[waveset]
        end_idx = zero_crossings#[waveset + 1] - 1
        waveset_length = end_idx - start_idx + 1
        
        new_length = max(2, round(waveset_length / amount))
        
        for new_sample from 1 to new_length
            orig_pos_relative = (new_sample - 1) / (new_length - 1)
            exact_pos = start_idx + orig_pos_relative * (waveset_length - 1)
            idx1 = floor(exact_pos)
            idx2 = idx1 + 1
            frac = exact_pos - idx1
            
            if idx2 <= end_idx
                value = samples#[idx1] * (1 - frac) + samples#[idx2] * frac
            else
                value = samples#[idx1]
            endif
            
            if output_index <= size(output_samples#)
                output_samples#[output_index] = value
                output_index += 1
            endif
        endfor
        
        if show_progress and (waveset mod ws_progress_interval = 0)
            appendInfo: "."
        endif
    endfor

elsif type = 6
    # RANDOMIZE waveset order
    waveset_indices# = zero#(n_wavesets)
    for i from 1 to n_wavesets
        waveset_indices#[i] = i
    endfor
    
    # Fisher-Yates shuffle
    n_to_shuffle = min(n_wavesets, round(n_wavesets * amount))
    for shuffle from 1 to n_to_shuffle
        i = randomInteger(1, n_wavesets)
        j = randomInteger(1, n_wavesets)
        temp = waveset_indices#[i]
        waveset_indices#[i] = waveset_indices#[j]
        waveset_indices#[j] = temp
    endfor
    
    for waveset_order from 1 to n_wavesets
        waveset = waveset_indices#[waveset_order]
        start_idx = zero_crossings#[waveset]
        end_idx = zero_crossings#[waveset + 1] - 1
        
        for sample from start_idx to end_idx
            if output_index <= size(output_samples#)
                output_samples#[output_index] = samples#[sample]
                output_index += 1
            endif
        endfor
        
        if show_progress and (waveset_order mod ws_progress_interval = 0)
            appendInfo: "."
        endif
    endfor

elsif type = 7
    # AMPLITUDE alternating
    for waveset from 1 to n_wavesets
        start_idx = zero_crossings#[waveset]
        end_idx = zero_crossings#[waveset + 1] - 1
        
        if waveset mod 2 = 1
            scale = amount
        else
            scale = 1.0 / amount
        endif
        
        for sample from start_idx to end_idx
            if output_index <= size(output_samples#)
                output_samples#[output_index] = samples#[sample] * scale
                output_index += 1
            endif
        endfor
        
        if show_progress and (waveset mod ws_progress_interval = 0)
            appendInfo: "."
        endif
    endfor
endif

if show_progress
    appendInfoLine: " done"
endif

# === FINALIZE OUTPUT ===
final_length = output_index - 1

if final_length <= 0
    exitScript: "Error: No output samples generated. Try different settings."
endif

# === PRESERVE LENGTH (optional) ===
if preserve_length = 1 and final_length != n_samples
    if show_progress
        appendInfoLine: "[4/5] Resampling to preserve length..."
    endif
    
    temp_samples# = zero#(n_samples)
    resample_interval = max(1, floor(n_samples / 20))
    
    for i from 1 to n_samples
        pos = (i - 1) / (n_samples - 1) * (final_length - 1) + 1
        idx = floor(pos)
        frac = pos - idx
        
        if idx >= final_length
            temp_samples#[i] = output_samples#[final_length]
        else
            temp_samples#[i] = output_samples#[idx] * (1 - frac) + output_samples#[idx + 1] * frac
        endif
        
        if show_progress and (i mod resample_interval = 0)
            appendInfo: "."
        endif
    endfor
    
    output_samples# = temp_samples#
    final_length = n_samples
    
    if show_progress
        appendInfoLine: " done"
    endif
else
    if show_progress
        appendInfoLine: "[4/5] Skipping resample (length not preserved)"
    endif
endif

# === CREATE OUTPUT SOUND ===
if show_progress
    appendInfoLine: "[5/5] Creating output sound..."
endif

result_duration_seconds = final_length / sampling_rate
result_sound = Create Sound from formula: soundName$ + "_WSD", 1, 0, result_duration_seconds, sampling_rate, "0"

write_interval = max(1, floor(final_length / 20))

for i from 1 to final_length
    Set value at sample number: 1, i, output_samples#[i]
    
    if show_progress and (i mod write_interval = 0)
        appendInfo: "."
    endif
endfor

if show_progress
    appendInfoLine: " done"
endif

# === NORMALIZE ===
Scale peak: 0.95

# === TIMING ===
elapsed = stopwatch - start_time
result_duration = Get total duration

# === SUMMARY ===
appendInfoLine: ""
appendInfoLine: "============================================"
appendInfoLine: "COMPLETE!"
appendInfoLine: "============================================"
appendInfoLine: ""
appendInfoLine: "Processing time: ", fixed$(elapsed, 1), " seconds"
appendInfoLine: ""
appendInfoLine: "Original: ", fixed$(original_duration, 3), "s (", n_samples, " samples)"
appendInfoLine: "Output:   ", fixed$(result_duration, 3), "s (", final_length, " samples)"
appendInfoLine: "Wavesets: ", n_wavesets
appendInfoLine: ""
appendInfoLine: "Time ratio: ", fixed$(result_duration / original_duration, 2), "x"
appendInfoLine: ""
appendInfoLine: "Output: ", soundName$, "_WSD"

selectObject: result_sound
Play