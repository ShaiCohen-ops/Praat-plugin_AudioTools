Copy... soundObj
a = Get number of samples

d1 = 2
d2 = 4
d3 = 8
d4 = 10

# --- Left channel processing (channel 1) ---
select Sound soundObj
Extract one channel: 1
for k from 1 to 2
    n = d'k'
    b = a / n
    Formula: "self[col+b] - self[col]"
endfor
Rename: "Left"

# --- Right channel processing (channel 2) ---
select Sound soundObj
Extract one channel: 2
for k from 3 to 4
    n = d'k'
    b = a / n
    Formula: "self[col+b] - self[col]"
endfor
Rename: "Right"

# --- Combine back into stereo ---
select Sound Left
plus Sound Right
Combine to stereo

Scale peak: 0.99
Play
