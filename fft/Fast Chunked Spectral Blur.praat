# Fast Chunked Spectral Blur Script
form Spectral Blur
    positive blur_radius 3.0
    positive chunk_size_seconds 2.0
endform

if numberOfSelected("Sound") <> 1
    exitScript: "Please select one Sound"
endif

sound_name$ = selected$("Sound")
sound = selected("Sound")
original_duration = Get total duration
sampling_rate = Get sampling frequency
total_samples = Get number of samples
channels = Get number of channels

writeInfoLine: "Starting fast chunked spectral blur..."
appendInfoLine: "Original duration: ", fixed$(original_duration, 3), " seconds"
appendInfoLine: "Blur radius: ", blur_radius
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
    
    appendInfoLine: "Processing chunk ", chunk, "/", num_chunks
    
    select sound
    start_time = (start_sample - 1) / sampling_rate
    end_time = (end_sample - 1) / sampling_rate
    
    if end_time > start_time
        chunk_sound = Extract part: start_time, end_time, "rectangular", 1, "no"
        
        # Process this chunk
        @processSpectralBlur: chunk_sound, blur_radius
        
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
Scale: 0.99
Rename: sound_name$ + "_blurred"

appendInfoLine: "Spectral blur complete!"
select results

# Spectral blur procedure for each chunk
procedure processSpectralBlur: .sound, .blur_radius
    select .sound
    .duration = Get total duration
    
    # Skip very short chunks
    if .duration < 0.05
        processed = Copy: "processed"
    else
        # Create spectrogram with optimized settings for chunk
        To Spectrogram: 0.025, 5000, 0.005, 20, "Gaussian"
        .spectrogram = selected("Spectrogram")
        
        # Convert to matrix
        select .spectrogram
        To Matrix
        .matrix = selected("Matrix")
        
        # Get dimensions
        .nx = Get number of columns
        .ny = Get number of rows
        
        # Set blur parameters
        .blur = round(.blur_radius)
        if .blur < 1
            .blur = 1
        endif
        
        # Create output matrix
        select .matrix
        Copy: "blurred"
        .blurred_matrix = selected("Matrix")
        
        # Fast blur processing - optimized for chunks
        appendInfoLine: "  Blurring ", .nx, " x ", .ny, " matrix..."
        
        # Process fewer frequency bins for speed
        if .ny > 100
            .bin_step = 2
        else
            .bin_step = 1
        endif
        
        for .frame from 1 to .nx
            # Process every 4th frame for speed
            if (.frame - 1) mod 4 <> 0
                goto next_frame
            endif
            
            for .bin from 1 to .ny
                # Process every nth bin for speed
                if .bin_step > 1 and (.bin - 1) mod .bin_step <> 0
                    goto next_bin
                endif
                # Get current value
                select .matrix
                .current_val = Get value in cell: .bin, .frame
                
                # Simple blur: average with frequency neighbors only
                .sum = .current_val
                .count = 1
                
                # Add frequency neighbors within blur radius
                for .offset from 1 to .blur
                    # Upper neighbor
                    if .bin + .offset <= .ny
                        .neighbor_val = Get value in cell: .bin + .offset, .frame
                        .sum = .sum + .neighbor_val
                        .count = .count + 1
                    endif
                    
                    # Lower neighbor  
                    if .bin - .offset >= 1
                        .neighbor_val = Get value in cell: .bin - .offset, .frame
                        .sum = .sum + .neighbor_val
                        .count = .count + 1
                    endif
                endfor
                
                # Set averaged value
                .new_val = .sum / .count
                select .blurred_matrix
                Set value: .bin, .frame, .new_val
                
                label next_bin
            endfor
            
            label next_frame
        endfor
        
        # Convert back to sound
        select .blurred_matrix
        To Spectrogram
        .blurred_spectrogram = selected("Spectrogram")
        
        select .blurred_spectrogram
        processed = To Sound: 44100
        
        # Clean up intermediate objects
        select .spectrogram
        plus .matrix
        plus .blurred_matrix
        plus .blurred_spectrogram
        Remove
    endif
endproc