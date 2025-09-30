# Simple Rate Panning 

form Panning
    real pan_rate 1.0
endform

# Select sound object
sound = selected("Sound")
selectObject: sound

# Check channels
num_channels = Get number of channels
if num_channels != 2
    exitScript: "Need stereo sound"
endif

# Create copy
selectObject: sound
Copy: "panned_result"

# Apply panning using separate Formulas for each channel
selectObject: "Sound panned_result"

# Left channel - sine wave modulation
Formula: "if col = 1 then self * (0.5 + 0.4 * sin(2*pi*pan_rate*x)) else self fi"

# Right channel - opposite modulation  
Formula: "if col = 2 then self * (0.5 + 0.4 * cos(2*pi*pan_rate*x)) else self fi"

# Play result
selectObject: "Sound panned_result"
Play
