# ============================================================
# Praat AudioTools - Fast Waveset Distortion.praat
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

# Fast Waveset Distortion Script
# Fixed version with proper procedure calls and error handling

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
    positive Chunk_size_seconds 0.5
endform

if numberOfSelected("Sound") = 0
    exitScript: "Please select a Sound object first."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")
original_duration = Get total duration
sampling_rate = Get sampling frequency
total_samples = Get number of samples
channels = Get number of channels

writeInfoLine: "Starting fast waveset distortion..."
appendInfoLine: "Original duration: ", fixed$(original_duration, 3), " seconds"
appendInfoLine: "Distortion type: ", type$
appendInfoLine: "Amount: ", amount
appendInfoLine: "Chunk size: ", chunk_size_seconds, " seconds"

chunk_size_samples = round(chunk_size_seconds * sampling_rate)
num_chunks = ceiling(total_samples / chunk_size_samples)

appendInfoLine: "Processing ", num_chunks, " chunks"

# Create empty sound to start with
select sound
results = Create Sound from formula: "temp_results", channels, 0, 0.001, sampling_rate, "0"

for chunk from 1 to num_chunks
    start_sample = (chunk - 1) * chunk_size_samples + 1
    end_sample = min(start_sample + chunk_size_samples - 1, total_samples)
    
    if start_sample > total_samples
        goto end_chunks
    endif
    
    appendInfoLine: "Chunk ", chunk, "/", num_chunks, " (samples ", start_sample, " to ", end_sample, ")"
    
    select sound
    start_time = (start_sample - 1) / sampling_rate
    end_time = (end_sample - 1) / sampling_rate
    
    if end_time > start_time
        chunk_sound = Extract part: start_time, end_time, "rectangular", 1, "no"
        
        select chunk_sound
        # Call the appropriate procedure based on type
        if type = 1
            @repeatWavesets: chunk_sound, amount
        elsif type = 2
            @skipWavesets: chunk_sound, amount
        elsif type = 3
            @reverseSound: chunk_sound
        elsif type = 4
            @stretchSound: chunk_sound, amount
        elsif type = 5
            @compressSound: chunk_sound, amount
        elsif type = 6
            @randomizeWavesets: chunk_sound, amount
        elsif type = 7
            @amplitudeScale: chunk_sound, amount
        else
            processed = Copy: "processed"
        endif
        
        # Combine with previous results
        select results
        current_duration = Get total duration
        
        if chunk = 1
            # First chunk - replace the empty sound
            select results
            Remove
            select processed
            results = Copy: "temp_results"
        else
            # Subsequent chunks - concatenate
            select results
            plus processed
            concatenated = Concatenate
            select results
            Remove
            results = concatenated
        endif
        
        # Clean up
        select chunk_sound
        Remove
        select processed
        Remove
    endif
endfor

label end_chunks

# Final processing
select results
if preserve_length = 1
    current_duration = Get total duration
    duration_ratio = current_duration / original_duration
    
    appendInfoLine: "Current duration: ", fixed$(current_duration, 3), " seconds"
    appendInfoLine: "Target duration: ", fixed$(original_duration, 3), " seconds"
    appendInfoLine: "Duration ratio: ", fixed$(duration_ratio, 3)
    
    if abs(duration_ratio - 1) > 0.01
        appendInfoLine: "Adjusting duration to preserve length..."
        
        # Use manipulation for large duration changes
        if duration_ratio > 1.5 or duration_ratio < 0.67
            manipulation = To Manipulation: 0.01, 75, 600
            select manipulation
            
            duration_tier = Extract duration tier
            select duration_tier
            # Scale factor is inverse of duration ratio
            scale_factor = 1 / duration_ratio
            Add point: 0, scale_factor
            Add point: current_duration, scale_factor
            
            select manipulation
            plus duration_tier
            Replace duration tier
            
            select manipulation
            adjusted = Get resynthesis (overlap-add)
            
            # Clean up manipulation objects
            select manipulation
            Remove
            select duration_tier
            Remove
            
            select results
            Remove
            results = adjusted
        else
            # Use resampling for small duration changes
            new_sampling_rate = sampling_rate * duration_ratio
            resampled = Resample: new_sampling_rate, 50
            select results
            Remove
            results = resampled
        endif
    endif
endif

select results
Scale: 0.99
Rename: soundName$ + "_WavesetDistorted"

result_duration = Get total duration
appendInfoLine: "Fast waveset distortion complete!"
appendInfoLine: "New duration: ", fixed$(result_duration, 3), " seconds"

select results

# Procedure definitions
procedure repeatWavesets: .sound, .amount
    select .sound
    .samples = Get number of samples
    .original_duration = Get total duration
    
    if .samples < 100
        processed = Copy: "processed"
    else
        .repetitions = round(.amount)
        if .repetitions > 4
            .repetitions = 4
        endif
        
        # For preserve_length mode, we need to fit repetitions into original duration
        if preserve_length = 1
            # Calculate how long each repetition should be
            .target_duration = .original_duration / .repetitions
            
            # Create first copy
            processed = Copy: "processed"
            
            # If we need to compress each repetition to fit
            if .target_duration < .original_duration * 0.9
                select processed
                manipulation = To Manipulation: 0.01, 75, 600
                select manipulation
                
                duration_tier = Extract duration tier
                select duration_tier
                .scale_factor = .target_duration / .original_duration
                Add point: 0, .scale_factor
                Add point: .original_duration, .scale_factor
                
                select manipulation
                plus duration_tier
                Replace duration tier
                
                select manipulation
                compressed_rep = Get resynthesis (overlap-add)
                
                select manipulation
                Remove
                select duration_tier
                Remove
                select processed
                Remove
                
                processed = compressed_rep
            endif
            
            # Create additional repetitions
            for .rep from 2 to .repetitions
                select processed
                temp_copy = Copy: "temp"
                select temp_copy
                .decay = 0.8^(.rep-1)
                Formula: "self * .decay"
                
                select processed
                plus temp_copy
                new_processed = Concatenate
                select processed
                Remove
                select temp_copy
                Remove
                processed = new_processed
            endfor
        else
            # Original behavior for non-preserve length mode
            processed = Copy: "processed"
            
            for .rep from 2 to .repetitions
                select .sound
                temp_copy = Copy: "temp"
                select temp_copy
                .decay = 0.8^(.rep-1)
                Formula: "self * .decay"
                
                select processed
                plus temp_copy
                new_processed = Concatenate
                select processed
                Remove
                select temp_copy
                Remove
                processed = new_processed
            endfor
        endif
    endif
endproc

procedure skipWavesets: .sound, .amount
    select .sound
    .samples = Get number of samples
    .channels = Get number of channels
    .sampling_rate = Get sampling frequency
    .duration = Get total duration
    
    # Skip this chunk with probability based on amount
    if randomUniform(0, 1) < (1/.amount)
        processed = Copy: "processed"
    else
        # Create silent sound with same duration as original chunk
        processed = Create Sound from formula: "processed", .channels, 0, .duration, .sampling_rate, "0"
    endif
endproc

procedure reverseSound: .sound
    select .sound
    processed = Copy: "processed"
    select processed
    Reverse
endproc

procedure stretchSound: .sound, .amount
    select .sound
    .original_duration = Get total duration
    .sampling_rate = Get sampling frequency
    .channels = Get number of channels
    
    # For proper time stretching without pitch change, use PSOLA
    if .amount > 1.05 or .amount < 0.95
        # Create manipulation object for time stretching
        manipulation = To Manipulation: 0.01, 75, 600
        select manipulation
        
        # Get the duration tier and scale it
        duration_tier = Extract duration tier
        select duration_tier
        Add point: 0, .amount
        Add point: .original_duration, .amount
        
        # Apply the duration changes
        select manipulation
        plus duration_tier
        Replace duration tier
        
        # Synthesize the result
        select manipulation
        processed = Get resynthesis (overlap-add)
        
        # Clean up
        select manipulation
        Remove
        select duration_tier
        Remove
    else
        processed = Copy: "processed"
    endif
endproc

procedure compressSound: .sound, .amount
    select .sound
    .original_duration = Get total duration
    .sampling_rate = Get sampling frequency
    .channels = Get number of channels
    
    # For proper time compression without pitch change, use PSOLA
    if .amount > 1.05 or .amount < 0.95
        # Create manipulation object for time compression
        manipulation = To Manipulation: 0.01, 75, 600
        select manipulation
        
        # Get the duration tier and scale it
        duration_tier = Extract duration tier
        select duration_tier
        Add point: 0, 1 / .amount
        Add point: .original_duration, 1 / .amount
        
        # Apply the duration changes
        select manipulation
        plus duration_tier
        Replace duration tier
        
        # Synthesize the result
        select manipulation
        processed = Get resynthesis (overlap-add)
        
        # Clean up
        select manipulation
        Remove
        select duration_tier
        Remove
    else
        processed = Copy: "processed"
    endif
endproc

procedure randomizeWavesets: .sound, .amount
    select .sound
    .duration = Get total duration
    
    # Simple randomization: either keep original or reverse
    if randomUniform(0, 1) < .amount/5
        # Reverse
        processed = Copy: "processed"
        select processed
        Reverse
    elsif randomUniform(0, 1) < .amount/5
        # Apply some other transformation
        processed = Copy: "processed"
        select processed
        Formula: "if randomUniform(0,1) < 0.3 then 0 else self fi"
    else
        # Keep original
        processed = Copy: "processed"
    endif
endproc

procedure amplitudeScale: .sound, .amount
    select .sound
    processed = Copy: "processed"
    select processed
    
    # Apply amplitude scaling
    if randomUniform(0, 1) > 0.5
        .scale = .amount
    else
        .scale = 1 / .amount
    endif
    
    Formula: "self * .scale"
    
    # Prevent clipping
    if .scale > 1.5
        Scale: 0.8
    elsif .scale > 1
        Scale: 0.9
    endif
endproc