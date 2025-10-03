form Soft Clipping Distortion
    comment This script applies soft clipping using tanh function
    comment Distortion parameters:
    positive drive_amount 8
    positive output_level 0.7
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
Copy: originalName$ + "_softclipped"

# Apply soft clipping distortion
Formula: "tanh(self * 'drive_amount') * 'output_level'"

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif