form Full-Wave Rectifier
    comment This script applies full-wave rectification to a sound
    comment (converts all negative values to positive)
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
Copy: originalName$ + "_rectified"

# Apply full-wave rectification (absolute value)
Formula: "abs(self)"

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif
