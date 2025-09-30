# Praat script: Create 8-channel file with speed deviations

form Create 8-channel speed-deviated file
    optionmenu Mode: 1
        option Automatic (using factor)
        option Manual (input all values)
        option Random deviation
    positive Speed_deviation_factor 0.15
    positive Channel_1_speed 0.85
    positive Channel_2_speed 0.88
    positive Channel_3_speed 0.91
    positive Channel_4_speed 0.94
    positive Channel_5_speed 1.06
    positive Channel_6_speed 1.09
    positive Channel_7_speed 1.12
    positive Channel_8_speed 1.15
    positive Random_min_speed 0.80
    positive Random_max_speed 1.20
    positive Random_seed 42
    boolean Override_sampling_frequency 1
    positive Target_sampling_frequency 44100
    boolean Show_info 1
endform

# Calculate or use manual speed factors
if mode = 1
    # Automatic mode - calculate from factor
    for i from 1 to 8
        speed_factors[i] = 1 - speed_deviation_factor + ((i-1) * (2 * speed_deviation_factor) / 7)
    endfor
elif mode = 2
    # Manual mode - use provided values
    speed_factors[1] = channel_1_speed
    speed_factors[2] = channel_2_speed
    speed_factors[3] = channel_3_speed
    speed_factors[4] = channel_4_speed
    speed_factors[5] = channel_5_speed
    speed_factors[6] = channel_6_speed
    speed_factors[7] = channel_7_speed
    speed_factors[8] = channel_8_speed
else
    # Random mode - generate pseudo-random speed factors within range
    # Simple pseudo-random based on seed for reproducibility
    for i from 1 to 8
        # Create pseudo-random value based on seed and channel number
        pseudo_random = (random_seed * i * 137 + 97) mod 1000 / 1000
        speed_factors[i] = random_min_speed + (random_max_speed - random_min_speed) * pseudo_random
    endfor
endif

# Check if a sound is selected
if numberOfSelected("Sound") = 0
    exitScript: "Please select a sound object first."
endif

sound = selected("Sound")
sound_name$ = selected$("Sound")

selectObject: sound
original_sampling_frequency = Get sampling frequency
original_duration = Get total duration

# Convert to mono if stereo
number_of_channels = Get number of channels
if number_of_channels > 1
    Convert to mono
    sound = selected("Sound")
    sound_name$ = selected$("Sound")
endif

# Override sampling frequency if requested
if override_sampling_frequency
    selectObject: sound
    Override sampling frequency: target_sampling_frequency
endif

# Create 8 copies with different speed deviations
for i from 1 to 8
    speed_factor = speed_factors[i]
    
    # Create a copy
    selectObject: sound
    Copy: "temp_channel_" + string$(i)
    sound_copy = selected("Sound")
    
    # Apply speed change using overlap-add
    selectObject: sound_copy
    
    # Ensure we have a mono sound for overlap-add
    current_channels = Get number of channels
    if current_channels > 1
        Convert to mono
        removeObject: sound_copy
        sound_copy = selected("Sound")
    endif
    
    min_pitch = 75
    max_pitch = 600
    target_duration = original_duration / speed_factor
    
    Lengthen (overlap-add): min_pitch, max_pitch, target_duration/original_duration
    removeObject: sound_copy
    
    # Store the processed sound
    processed_sound = selected("Sound")
    
    # Resample to target frequency
    selectObject: processed_sound
    Resample: target_sampling_frequency, 50
    removeObject: processed_sound
    
    # Store final resampled sound
    sounds[i] = selected("Sound")
    
    # Rename for clarity (optional)
    Rename: sound_name$ + "_ch" + string$(i) + "_" + fixed$(speed_factor, 3)
endfor

# Create the 8-channel sound by combining all copies
selectObject: sounds[1]
for i from 2 to 8
    plusObject: sounds[i]
endfor

Combine to stereo

# Rename the final multi-channel sound
Rename: sound_name$ + "_8channel_speed_variations"

# Store original sound ID for preservation
original_sound_id = sound

# Clean up all temporary objects
for i from 1 to 8
    removeObject: sounds[i]
endfor

# Remove the temporary mono conversion if it was created
if number_of_channels > 1
    removeObject: sound
endif

# Clean up any remaining temporary Sound objects
# Keep only the original input and final 8-channel output
final_sound_id = selected("Sound")

# Remove all Sound objects except original and final
select all
n_sounds = numberOfSelected("Sound")
if n_sounds > 0
    for i from n_sounds to 1
        current_sound = selected("Sound", i)
        if current_sound != original_sound_id and current_sound != final_sound_id
            removeObject: current_sound
        endif
    endfor
endif

# Select the final result
selectObject: final_sound_id

# Select the final result
final_sound = selected("Sound")
selectObject: final_sound

# Display info if requested
if show_info
    duration = Get total duration
    final_channels = Get number of channels
    sampling_rate = Get sampling frequency
    
    beginPause: "Processing Complete"
        comment: "SUCCESS: Created 8-channel sound!"
        comment: "File: " + selected$("Sound")
        comment: "Duration: " + fixed$(duration, 2) + " seconds"
        comment: "Channels: " + string$(final_channels)
        comment: "Sampling rate: " + string$(sampling_rate) + " Hz"
        comment: ""
        comment: "Speed factors used:"
        for i from 1 to 8
            comment: "Channel " + string$(i) + ": " + fixed$(speed_factors[i], 3) + " (" + fixed$((speed_factors[i] - 1) * 100, 1) + "%)"
        endfor
        comment: ""
        if mode = 1
            comment: "Mode: Automatic (factor: " + fixed$(speed_deviation_factor, 3) + ")"
        elif mode = 2
            comment: "Mode: Manual input"
        else
            comment: "Mode: Random deviation (min: " + fixed$(random_min_speed, 3) + ", max: " + fixed$(random_max_speed, 3) + ", seed: " + string$(random_seed) + ")"
        endif
        if override_sampling_frequency
            comment: "Sampling frequency overridden to: " + string$(target_sampling_frequency) + " Hz"
        endif
    endPause: "OK", 1
endif