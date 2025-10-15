# DBAP (Distance-Based Amplitude Panning) with Movement Control
# Creates multichannel audio with moving sound source
clearinfo
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one sound object."
endif

# Get selected sound info
sound = selected("Sound")
selectObject: sound
sound_name$ = selected$("Sound")
duration = Get total duration
original_fs = Get sampling frequency

form DBAP Movement Control
    comment Movement trajectory settings:
    optionmenu movement_type: 1
        option Linear
        option Circular
        option Figure-8
        option Spiral In
        option Spiral Out
        option Pendulum
        option Zigzag
        option Random Walk
        option Ellipse
        option Square
    real start_x -1.0
    real start_y 0.0
    real end_x 1.0
    real end_y 0.0
    real radius 0.4
    real speed 1.0
    
    comment Speaker configuration:
    optionmenu preset: 1
        option Stereo (2 speakers)
        option Triangle (3 speakers)
        option Quad (4 speakers)
        option Pentagon (5 speakers)
        option Hexagon (6 speakers)
        option Surround 5.1 (6 speakers)
        option Surround 7.1 (8 speakers)
        option Octagon (8 speakers)
    
    comment Processing settings:
    positive chunk_duration 0.05
    positive rolloff 1.0
    boolean normalize_gains 1
endform

# Speaker presets
if preset = 1
    # Stereo
    number_of_speakers = 2
    speakerX1 = -1.0
    speakerY1 = 0.0
    speakerX2 = 1.0
    speakerY2 = 0.0
    
elsif preset = 2
    # Triangle
    number_of_speakers = 3
    speakerX1 = -0.866
    speakerY1 = -0.5
    speakerX2 = 0.866
    speakerY2 = -0.5
    speakerX3 = 0.0
    speakerY3 = 1.0
    
elsif preset = 3
    # Quad
    number_of_speakers = 4
    speakerX1 = -1.0
    speakerY1 = -1.0
    speakerX2 = 1.0
    speakerY2 = -1.0
    speakerX3 = -1.0
    speakerY3 = 1.0
    speakerX4 = 1.0
    speakerY4 = 1.0

elsif preset = 4
    # Pentagon
    number_of_speakers = 5
    for i to 5
        angle = (i - 1) * 2 * pi / 5 - pi / 2
        speakerX'i' = cos(angle)
        speakerY'i' = sin(angle)
    endfor

elsif preset = 5
    # Hexagon
    number_of_speakers = 6
    for i to 6
        angle = (i - 1) * 2 * pi / 6
        speakerX'i' = cos(angle)
        speakerY'i' = sin(angle)
    endfor
    
elsif preset = 6
    # 5.1 Surround
    number_of_speakers = 6
    speakerX1 = -1.0    # Left
    speakerY1 = 0.0
    speakerX2 = 1.0     # Right
    speakerY2 = 0.0
    speakerX3 = 0.0     # Center
    speakerY3 = 1.0
    speakerX4 = -0.7    # Left surround
    speakerY4 = -0.7
    speakerX5 = 0.7     # Right surround
    speakerY5 = -0.7
    speakerX6 = 0.0     # LFE (positioned centrally)
    speakerY6 = 0.0

elsif preset = 7
    # 7.1 Surround
    number_of_speakers = 8
    speakerX1 = -1.0    # Left
    speakerY1 = 0.0
    speakerX2 = 1.0     # Right
    speakerY2 = 0.0
    speakerX3 = 0.0     # Center
    speakerY3 = 1.0
    speakerX4 = -0.7    # Side left
    speakerY4 = 0.7
    speakerX5 = 0.7     # Side right
    speakerY5 = 0.7
    speakerX6 = -0.7    # Rear left
    speakerY6 = -0.7
    speakerX7 = 0.7     # Rear right
    speakerY7 = -0.7
    speakerX8 = 0.0     # LFE
    speakerY8 = 0.0

elsif preset = 8
    # Octagon
    number_of_speakers = 8
    for i to 8
        angle = (i - 1) * 2 * pi / 8
        speakerX'i' = cos(angle)
        speakerY'i' = sin(angle)
    endfor
endif

# Convert to mono if needed
selectObject: sound
num_channels = Get number of channels
if num_channels > 1
    appendInfoLine: "Converting to mono..."
    monoSound = Convert to mono
else
    monoSound = Copy: "mono_copy"
endif

selectObject: monoSound
fs = Get sampling frequency

# Calculate number of chunks
num_chunks = ceiling(duration / chunk_duration)

appendInfoLine: "Processing DBAP with ", number_of_speakers, " speakers..."
appendInfoLine: "Duration: ", fixed$(duration, 3), " seconds"
appendInfoLine: "Chunk duration: ", fixed$(chunk_duration, 3), " seconds"
appendInfoLine: "Number of chunks: ", num_chunks

# Initialize speaker sound arrays
for speaker to number_of_speakers
    speakerSound'speaker' = 0
endfor

# Process in chunks
for chunk to num_chunks
    chunk_start = (chunk - 1) * chunk_duration
    chunk_end = chunk_start + chunk_duration
    if chunk_end > duration
        chunk_end = duration
    endif
    
    # Calculate progress through sound (middle of chunk)
    chunk_middle = (chunk_start + chunk_end) / 2
    progress = chunk_middle / duration
    
    # Calculate source position based on movement type
    if movement_type = 1
        # Linear movement
        source_x = start_x + (end_x - start_x) * progress
        source_y = start_y + (end_y - start_y) * progress
        
    elsif movement_type = 2
        # Circular movement (centered at origin)
        angle = progress * 2 * pi * speed
        source_x = radius * cos(angle)
        source_y = radius * sin(angle)
        
    elsif movement_type = 3
        # Figure-8 movement (centered at origin)
        angle = progress * 4 * pi * speed
        source_x = radius * sin(angle)
        source_y = radius * sin(2 * angle) / 2

    elsif movement_type = 4
        # Spiral In
        angle = progress * 4 * pi * speed
        current_radius = radius * (1 - progress)
        source_x = current_radius * cos(angle)
        source_y = current_radius * sin(angle)

    elsif movement_type = 5
        # Spiral Out
        angle = progress * 4 * pi * speed
        current_radius = radius * progress
        source_x = current_radius * cos(angle)
        source_y = current_radius * sin(angle)

    elsif movement_type = 6
        # Pendulum (swinging left-right)
        swing_angle = sin(progress * pi * speed * 4) * pi / 3
        source_x = radius * sin(swing_angle)
        source_y = -radius * cos(swing_angle) * 0.5

    elsif movement_type = 7
        # Zigzag
        num_zigs = 4 * speed
        zig_progress = (progress * num_zigs) mod 1
        zig_num = floor(progress * num_zigs)
        if zig_num mod 2 = 0
            source_x = -radius + 2 * radius * zig_progress
        else
            source_x = radius - 2 * radius * zig_progress
        endif
        source_y = -radius + 2 * radius * progress

    elsif movement_type = 8
        # Random Walk (deterministic based on progress)
        angle1 = progress * 137.5 * speed
        angle2 = progress * 97.3 * speed
        source_x = radius * sin(angle1) * 0.7
        source_y = radius * cos(angle2) * 0.7

    elsif movement_type = 9
        # Ellipse
        angle = progress * 2 * pi * speed
        source_x = radius * 1.4 * cos(angle)
        source_y = radius * 0.7 * sin(angle)

    elsif movement_type = 10
        # Square path
        side_progress = (progress * 4 * speed) mod 1
        side_num = floor((progress * 4 * speed) mod 4)
        if side_num = 0
            # Top side: left to right
            source_x = -radius + 2 * radius * side_progress
            source_y = radius
        elsif side_num = 1
            # Right side: top to bottom
            source_x = radius
            source_y = radius - 2 * radius * side_progress
        elsif side_num = 2
            # Bottom side: right to left
            source_x = radius - 2 * radius * side_progress
            source_y = -radius
        else
            # Left side: bottom to top
            source_x = -radius
            source_y = -radius + 2 * radius * side_progress
        endif
    endif
    
    # Calculate gains for each speaker using DBAP
    total_power = 0
    for speaker to number_of_speakers
        # Get speaker position
        sp_x = speakerX'speaker'
        sp_y = speakerY'speaker'
        
        # Calculate distance
        dx = source_x - sp_x
        dy = source_y - sp_y
        distance = sqrt(dx * dx + dy * dy)
        
        # Avoid division by zero
        min_distance = 0.01
        if distance < min_distance
            distance = min_distance
        endif
        
        # DBAP: gain proportional to 1/distance^rolloff
        gain'speaker' = 1 / (distance ^ rolloff)
        total_power = total_power + (gain'speaker' * gain'speaker')
    endfor
    
    # Normalize gains to maintain constant power
    if normalize_gains and total_power > 0
        normalization = sqrt(total_power)
        for speaker to number_of_speakers
            gain'speaker' = gain'speaker' / normalization
        endfor
    endif
    
    # Extract chunk from source
    selectObject: monoSound
    chunkSound = Extract part: chunk_start, chunk_end, "rectangular", 1, "no"
    
    # Apply gains and build speaker sounds
    for speaker to number_of_speakers
        selectObject: chunkSound
        gainedChunk = Copy: "gained"
        
        # Apply gain using Formula
        current_gain = gain'speaker'
        Formula: "self * current_gain"
        
        # Concatenate to speaker sound
        if speakerSound'speaker' = 0
            # First chunk
            speakerSound'speaker' = gainedChunk
        else
            # Append chunk
            selectObject: speakerSound'speaker'
            plusObject: gainedChunk
            tempSound = Concatenate
            removeObject: speakerSound'speaker'
            removeObject: gainedChunk
            speakerSound'speaker' = tempSound
        endif
    endfor
    
    removeObject: chunkSound
    
    # Progress update
    if chunk mod 10 = 0 or chunk = num_chunks
        percent = (chunk / num_chunks) * 100
        appendInfoLine: "Processed chunk ", chunk, "/", num_chunks, " (", fixed$(percent, 1), "%)"
        appendInfoLine: "  Position: x=", fixed$(source_x, 3), ", y=", fixed$(source_y, 3)
    endif
endfor

# Combine all speaker sounds into multichannel sound
appendInfoLine: "Combining channels..."
selectObject: speakerSound1
for speaker from 2 to number_of_speakers
    plusObject: speakerSound'speaker'
endfor

if number_of_speakers = 2
    combinedSound = Combine to stereo
else
    combinedSound = Combine to stereo
endif
selectObject: combinedSound
Rename: sound_name$ + "_DBAP_" + string$(number_of_speakers) + "ch"
resultSound = combinedSound

# Final info
selectObject: resultSound
channels = Get number of channels
result_duration = Get total duration

appendInfoLine: ""
appendInfoLine: "=== DBAP Processing Complete ==="
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Channels: ", channels
appendInfoLine: "Duration: ", fixed$(result_duration, 3), "s"
appendInfoLine: "Sampling frequency: ", fs, " Hz"

# Play result
selectObject: resultSound
Play

# Cleanup temporary objects
removeObject: monoSound
for speaker to number_of_speakers
    removeObject: speakerSound'speaker'
endfor

# Keep only original and result
selectObject: resultSound

appendInfoLine: "Done! Original sound and DBAP result are selected."