form Stereo Channel Processing
    comment Left channel divisors (iterations 1-2):
    positive divisor_1 2
    positive divisor_2 4
    comment Right channel divisors (iterations 3-4):
    positive divisor_3 8
    positive divisor_4 10
    comment Left channel iteration range:
    natural left_start 1
    natural left_end 2
    comment Right channel iteration range:
    natural right_start 3
    natural right_end 4
    comment Output options:
    positive scale_peak 0.99
    boolean play_after_processing 1
endform

# Copy the sound object
Copy... soundObj

# Get the number of samples
a = Get number of samples

# Store divisors
d1 = divisor_1
d2 = divisor_2
d3 = divisor_3
d4 = divisor_4

# --- Left channel processing (channel 1) ---
select Sound soundObj
Extract one channel: 1
for k from left_start to left_end
    n = d'k'
    b = a / n
    Formula: "self[col+b] - self[col]"
endfor
Rename: "Left"

# --- Right channel processing (channel 2) ---
select Sound soundObj
Extract one channel: 2
for k from right_start to right_end
    n = d'k'
    b = a / n
    Formula: "self[col+b] - self[col]"
endfor
Rename: "Right"

# --- Combine back into stereo ---
select Sound Left
plus Sound Right
Combine to stereo
Rename: "soundObj_stereo"
Scale peak: scale_peak

# Clean up temporary objects
select Sound Left
plus Sound Right
plus Sound soundObj
Remove

# Play if requested
select Sound soundObj_stereo
if play_after_processing
    Play
endif