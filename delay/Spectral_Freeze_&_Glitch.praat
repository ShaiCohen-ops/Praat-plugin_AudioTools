form Time Freeze Effect Processing
    comment Freeze parameters:
    natural freeze_points 12
    positive freeze_duration_divisor 25
    comment Freeze length variation:
    positive freeze_length_min_factor 0.5
    positive freeze_length_max_factor 1.5
    positive freeze_repeat_divisor 3
    comment Spectral artifacts:
    positive artifact_amplitude 0.1
    comment Output options:
    positive scale_peak 0.91
    boolean play_after_processing 1
    comment Random seed (optional, leave unchecked for random):
    boolean use_random_seed 0
    positive random_seed 12345
endform

# Copy the sound object
Copy... soundObj

# Get the number of samples
a = Get number of samples

# Set random seed if specified
if use_random_seed
    random_seed_value = random_seed
endif

# Calculate freeze duration
freezeDuration = a / freeze_duration_divisor

# Main freeze processing loop
for point from 1 to freeze_points
    # Random freeze position
    freezePos = randomInteger(floor(freezeDuration), a - floor(freezeDuration))
    freezeLength = randomInteger(floor(freezeDuration * freeze_length_min_factor), floor(freezeDuration * freeze_length_max_factor))
    
    # Freeze and repeat segment
    Formula: "if col >= freezePos and col < freezePos + freezeLength then self[freezePos + ((col - freezePos) mod (freezeLength/'freeze_repeat_divisor'))] else self fi"
    
    # Add spectral artifacts
    Formula: "self * (1 + 'artifact_amplitude' * sin(2 * pi * point * col / a))"
endfor

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif