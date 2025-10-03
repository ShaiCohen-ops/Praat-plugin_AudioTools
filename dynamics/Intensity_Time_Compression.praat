form Intensity Time Compression
    comment This script compresses the intensity envelope in time
    comment Intensity extraction parameters:
    positive minimum_pitch 100
    positive time_step 0.1
    boolean subtract_mean yes
    comment Time compression parameters:
    positive compression_factor 2
    comment (2 = compress to half duration, 4 = quarter duration, etc.)
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

# Get duration
duration = Get total duration

# Copy the sound
b = Copy: originalName$ + "_time_compressed"

# Extract intensity
intens = To Intensity: minimum_pitch, time_step, subtract_mean

# Compress intensity timeline
compressed_duration = duration / compression_factor
Scale times to: 0, compressed_duration

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
    plus intens
    plus c
    Remove
endif