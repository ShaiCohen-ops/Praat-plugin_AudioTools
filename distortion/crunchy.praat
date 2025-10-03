form Bit Crushing Effect
    comment This script applies bit crushing (quantization) to a sound
    comment Bit crushing parameters:
    positive quantization_levels 4
    comment Output options:
    positive scale_peak 0.99
    boolean play_after_processing 1
endform

# Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# Get the name of the original sound
originalName$ = selected$("Sound")

# Copy the sound object
Copy: originalName$ + "_bitcrushed"

# Apply bit crushing (quantization)
Formula: "round(self * 'quantization_levels') / 'quantization_levels'"

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif
