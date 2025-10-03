form Intensity Wave Inversion
    comment This script inverts intensity values around a midpoint
    comment Intensity extraction parameters:
    positive minimum_pitch 100
    positive time_step 0.1
    boolean subtract_mean yes
    comment Inversion parameters:
    positive inversion_midpoint 100
    comment (intensity values will be inverted around this point)
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
b = Copy: originalName$ + "_intensity_inverted"

# Extract intensity
intens = To Intensity: minimum_pitch, time_step, subtract_mean

# Invert intensity values around midpoint
Formula: "'inversion_midpoint' - self"

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
