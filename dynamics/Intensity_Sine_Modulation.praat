form Intensity Sine Modulation
    comment This script modulates intensity with a sine wave
    comment Intensity extraction parameters:
    positive minimum_pitch 100
    positive time_step 0.1
    boolean subtract_mean yes
    comment Sine modulation parameters:
    positive modulation_frequency 10
    positive modulation_center 0.5
    positive modulation_depth 0.5
    comment (intensity will vary between center-depth and center+depth)
    comment Multiply parameters:
    boolean scale_intensities yes
    comment Output options:
    boolean play_after_processing 1
    boolean keep_intermediate_objects 0
endform

# Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# Store original sound
a = selected("Sound")
originalName$ = selected$("Sound")

# Copy the sound
b = Copy: originalName$ + "_sine_modulated"

# Extract intensity
To Intensity: minimum_pitch, time_step, subtract_mean

# Apply sine wave modulation
Formula: "self * ('modulation_center' + 'modulation_depth' * sin(x * 'modulation_frequency'))"

# Convert to IntensityTier
c = Down to IntensityTier

# Select sound and intensity tier, then multiply
select a
plus c
Multiply: scale_intensities

# Rename result
Rename: originalName$ + "_result"

# Play if requested
if play_after_processing
    Play
endif

# Clean up intermediate objects unless requested to keep
if not keep_intermediate_objects
    select b
    Remove
    select c
    Remove
endif
