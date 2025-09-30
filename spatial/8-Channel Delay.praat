# -------------------------------------------
# 8-Channel Delay Processor (Praat)
# Works on the selected Sound; auto-converts to mono.
# Outputs a stereo mix of 8 delayed variants.
# -------------------------------------------

# Require a selected Sound
if numberOfSelected ("Sound") = 0
    pause "Select a Sound object and run again."
endif

# Work from the selected sound
selectObject: selected ("Sound")

# Ensure mono
nch = Get number of channels
if nch > 1
    Convert to mono
endif
Rename: "soundObj"

# Base info
a = Get number of samples

# --- Delays per channel (edit as desired) ---
d1 = 2
d2 = 4
d3 = 8
d4 = 10
d5 = 12
d6 = 16
d7 = 20
d8 = 24

# --- Build 8 delayed channels from the mono source ---
for i from 1 to 8
    select Sound soundObj
    Copy... Ch'i'
    n = d'i'
    b = floor (a / n)
    Formula: "if col + 'b' <= ncol then self[col + 'b'] - self[col] else -self[col] fi"
endfor

# --- Combine Ch1..Ch8 into stereo ---
select Sound Ch1
plus Sound Ch2
plus Sound Ch3
plus Sound Ch4
plus Sound Ch5
plus Sound Ch6
plus Sound Ch7
plus Sound Ch8
Combine to stereo
Rename: "StereoOut"

# --- Normalize & audition ---
select Sound StereoOut
Scale peak: 0.99
Play

# --- Remove intermediate objects ---
select Sound soundObj
plus Sound Ch1
plus Sound Ch2
plus Sound Ch3
plus Sound Ch4
plus Sound Ch5
plus Sound Ch6
plus Sound Ch7
plus Sound Ch8
Remove
