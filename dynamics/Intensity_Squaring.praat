form Intensity Squaring
    comment This script squares intensity values for sharper dynamics
    comment Intensity extraction parameters:
    positive minimum_pitch 100
    positive time_step 0.1
    boolean subtract_mean yes
    comment Squaring parameters:
    positive exponent 2
    positive intensity_scale 100
    comment (values are normalized by this scale before and after exponent)
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
b = Copy: originalName$ + "_squared"

# Extract intensity
To Intensity: minimum_pitch, time_step, subtract_mean

# Apply squaring formula (or custom exponent)
Formula: "(self/'intensity_scale')^'exponent' * 'intensity_scale'"

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
