form Compressor
    natural compression_percentage_(1-100) 25
    comment Compression parameters:
    positive compression_multiplier 10
    comment Output options:
    positive scale_peak 0.99
    boolean play_after_processing 1
endform

# Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# Limit compression to 100%
if compression_percentage > 100
    compression_percentage = 100
endif

# Calculate compression factor
comp = compression_percentage / 100

# Get the name of the original sound
s$ = selected$("Sound")

# Copy and compress
wrk = Copy: s$ + "_compressed"

# Apply compression formula
Formula: "self / (1 + abs(self) * 'comp' * 'compression_multiplier')"

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif