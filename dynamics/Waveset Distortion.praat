# ============================================================
# Praat AudioTools - Waveset Distortion.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Dynamic range or envelope control script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# Waveset Distortion Script
# Based on CDP's waveset manipulation concepts
# Wavesets are pseudo-wavecycles defined as segments between zero-crossings

form Waveset Distortion
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
endform

# Check if a sound is selected
if numberOfSelected("Sound") = 0
    exitScript: "Please select a Sound object first."
endif

# Get the selected sound
sound = selected("Sound")
soundName$ = selected$("Sound")
original_duration = Get total duration

# Get sound properties
sampling_rate = Get sampling frequency
total_samples = Get number of samples
duration = Get total duration

writeInfoLine: "Starting waveset distortion..."
appendInfoLine: "Original duration: ", fixed$(duration, 3), " seconds"
appendInfoLine: "Distortion type: ", type$
appendInfoLine: "Amount: ", amount
appendInfoLine: "Preserve length: ", preserve_length

# Extract samples into arrays
n_samples = Get number of samples
samples# = zero#(n_samples)

# Extract all samples directly from Sound object
for i from 1 to n_samples
    samples#[i] = Get value at sample number: i
endfor

# Find zero crossings to define wavesets
zero_crossings# = zero#(n_samples)
n_crossings = 0

# Find zero crossings - sign changes
for i from 2 to n_samples
    if (samples#[i-1] >= 0 and samples#[i] < 0) or (samples#[i-1] < 0 and samples#[i] >= 0)
        n_crossings += 1
        zero_crossings#[n_crossings] = i
    endif
endfor

appendInfoLine: "Found ", n_crossings, " zero crossings"
appendInfoLine: "Number of wavesets: ", n_crossings - 1

if n_crossings < 3
    exitScript: "Not enough zero crossings found for waveset processing."
endif

# Create new sample array for output
# Allocate extra space
output_samples# = zero#(n_samples * 10)
output_index = 1

# Process wavesets based on distortion type
if type = 1
    # Repeat wavesets
    appendInfoLine: "Applying waveset repetition with factor ", amount
    
    for waveset from 1 to n_crossings - 1
        start_idx = zero_crossings#[waveset]
        end_idx = zero_crossings#[waveset + 1] - 1
        waveset_length = end_idx - start_idx + 1
        
        # Copy original waveset
        for sample from start_idx to end_idx
            if output_index <= size(output_samples#)
                output_samples#[output_index] = samples#[sample]
                output_index += 1
            endif
        endfor
        
        # Add repetitions with slight amplitude decay
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
    endfor

elsif type = 2
    # Skip wavesets
    appendInfoLine: "Applying waveset skipping with ratio ", amount
    
    skipped_count = 0
    for waveset from 1 to n_crossings - 1
        # Randomly decide whether to include this waveset
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
    endfor
    appendInfoLine: "Skipped ", skipped_count, " wavesets"

elsif type = 3
    # Reverse wavesets - SIMPLIFIED APPROACH
    appendInfoLine: "Applying waveset reversal"
    
    # Simple reverse: just reverse all samples
    for i to n_samples
        reverse_idx = n_samples - i + 1
        if output_index <= size(output_samples#)
            output_samples#[output_index] = samples#[reverse_idx]
            output_index += 1
        endif
    endfor

elsif type = 4
    # Stretch wavesets - ACTUAL TIME STRETCHING
    appendInfoLine: "Applying waveset time stretching with factor ", amount
    
    for waveset from 1 to n_crossings - 1
        start_idx = zero_crossings#[waveset]
        end_idx = zero_crossings#[waveset + 1] - 1
        waveset_length = end_idx - start_idx + 1
        
        # For time stretching, we need to interpolate more samples
        new_length = round(waveset_length * amount)
        if new_length < 2
            new_length = 2
        endif
        
        # Use proper interpolation for time stretching
        for new_sample from 1 to new_length
            # Calculate position in original waveset (0 to 1 range)
            orig_pos_relative = (new_sample - 1) / (new_length - 1)
            
            # Convert to actual sample position with fractional part
            exact_pos = start_idx + orig_pos_relative * (waveset_length - 1)
            idx1 = floor(exact_pos)
            idx2 = idx1 + 1
            frac = exact_pos - idx1
            
            # Linear interpolation between samples
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
    endfor

elsif type = 5
    # Compress wavesets - ACTUAL TIME COMPRESSION
    appendInfoLine: "Applying waveset time compression with factor ", amount
    
    for waveset from 1 to n_crossings - 1
        start_idx = zero_crossings#[waveset]
        end_idx = zero_crossings#[waveset + 1] - 1
        waveset_length = end_idx - start_idx + 1
        
        # For time compression, we skip samples (playback faster)
        new_length = max(2, round(waveset_length / amount))
        
        # Use proper interpolation for time compression
        for new_sample from 1 to new_length
            # Calculate position in original waveset (0 to 1 range)
            orig_pos_relative = (new_sample - 1) / (new_length - 1)
            
            # Convert to actual sample position with fractional part
            exact_pos = start_idx + orig_pos_relative * (waveset_length - 1)
            idx1 = floor(exact_pos)
            idx2 = idx1 + 1
            frac = exact_pos - idx1
            
            # Linear interpolation between samples
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
    endfor

elsif type = 6
    # Randomize waveset order
    appendInfoLine: "Applying waveset randomization with factor ", amount
    
    # Create array of waveset indices
    waveset_indices# = zero#(n_crossings - 1)
    for i from 1 to n_crossings - 1
        waveset_indices#[i] = i
    endfor
    
    # Shuffle some wavesets based on amount
    n_to_shuffle = round((n_crossings - 1) * amount)
    for shuffle from 1 to n_to_shuffle
        i = randomInteger(1, n_crossings - 1)
        j = randomInteger(1, n_crossings - 1)
        temp = waveset_indices#[i]
        waveset_indices#[i] = waveset_indices#[j]
        waveset_indices#[j] = temp
    endfor
    
    # Output wavesets in new order
    for waveset_order from 1 to n_crossings - 1
        waveset = waveset_indices#[waveset_order]
        start_idx = zero_crossings#[waveset]
        end_idx = zero_crossings#[waveset + 1] - 1
        
        for sample from start_idx to end_idx
            if output_index <= size(output_samples#)
                output_samples#[output_index] = samples#[sample]
                output_index += 1
            endif
        endfor
    endfor

elsif type = 7
    # Amplitude scale wavesets
    appendInfoLine: "Applying waveset amplitude scaling with factor ", amount
    
    for waveset from 1 to n_crossings - 1
        start_idx = zero_crossings#[waveset]
        end_idx = zero_crossings#[waveset + 1] - 1
        
        # Apply different scaling to alternating wavesets
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
    endfor
endif

# Adjust output length
final_length = output_index - 1
appendInfoLine: "Output samples: ", final_length
appendInfoLine: "Original samples: ", n_samples

# Check if we have any output samples
if final_length <= 0
    exitScript: "Error: No output samples were generated. Try a different distortion type or amount."
endif

# Handle length preservation ONLY if requested
if preserve_length = 1 and final_length != n_samples
    # Resample to preserve original length using manual interpolation
    appendInfoLine: "Resampling to preserve original length..."
    temp_samples# = zero#(n_samples)
    
    for i from 1 to n_samples
        # Calculate position in output array
        pos = (i - 1) / (n_samples - 1) * (final_length - 1) + 1
        idx = floor(pos)
        frac = pos - idx
        
        if idx >= final_length
            temp_samples#[i] = output_samples#[final_length]
        else
            temp_samples#[i] = output_samples#[idx] * (1 - frac) + output_samples#[idx + 1] * frac
        endif
    endfor
    
    output_samples# = temp_samples#
    final_length = n_samples
else
    appendInfoLine: "Length NOT preserved - allowing time stretching/compression"
endif

# Ensure we have a valid duration
if final_length <= 0
    exitScript: "Error: Final sound length is zero. Processing failed."
endif

# Calculate duration safely
result_duration_seconds = final_length / sampling_rate

# Create new Sound object with processed samples
resultSoundName$ = "WavesetDistorted"
select sound
result_sound = Create Sound from formula: resultSoundName$, 1, 0, result_duration_seconds, sampling_rate, "0"

# Fill Sound with processed samples
for i from 1 to final_length
    select result_sound
    Set value at sample number: i, output_samples#[i]
endfor

# Scale to avoid clipping
select result_sound
Scale: 0.99

# Get the final duration
result_duration = Get total duration

appendInfoLine: "Waveset distortion complete!"
appendInfoLine: "New duration: ", fixed$(result_duration, 3), " seconds"
appendInfoLine: "Time change factor: ", fixed$(result_duration/original_duration, 3)

# Select the result
select result_sound