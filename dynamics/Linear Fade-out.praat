form Compression with Exponential Fade
    comment This script applies soft compression and exponential fade-out
    comment Compression parameters:
    positive compression_denominator 4
    comment (controls compression amount: higher = less compression)
    comment Exponential fade parameters:
    positive fade_base 20
    comment (higher values = faster fade, lower = slower fade)
    boolean invert_fade 0
    comment (check for fade-in instead of fade-out)
    comment Output options:
    positive scale_peak 0.99
    boolean play_after_processing 1
endform

# Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# Copy the sound object
Copy... soundObj

# Get name and ID
name$ = selected$("Sound") + "_Compressed"
sound = selected("Sound")

# Apply soft compression
Formula: "self / (1 + (self^2) / 'compression_denominator')"

# Apply exponential fade
if invert_fade
    # Fade-in: increases from 0 to 1
    Formula: "self * ('fade_base'^((x-xmin)/(xmax-xmin)) / 'fade_base')"
else
    # Fade-out: decreases from 1 to 0
    Formula: "self * ('fade_base'^(-(x-xmin)/(xmax-xmin)))"
endif

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif