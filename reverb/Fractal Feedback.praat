# VARIATION 2: "Fractal Feedback" - Self-modulating delays
Copy... soundObj
depth = 3
a = Get number of samples
for layer from 1 to depth
    divisions = 2^layer
    for segment from 1 to divisions
        segment_size = a / divisions
        delay_offset = segment_size * randomUniform(0.1, 0.9)
        feedback_strength = 0.6 / layer
        Formula: "self + 'feedback_strength' * (self[col+'delay_offset'] - self[col]) * sin(2*pi*col/'segment_size')"
    endfor
endfor
Scale peak: 0.99
Play
