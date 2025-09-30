# EUCLIDEAN RHYTHM IMPULSES → convolve with a COPY of the selected sound

# 1) need a selected Sound
if numberOfSelected ("Sound") < 1
    exitScript: "Select a Sound in the Objects window first."
endif

# copy the selection to "XXXX"
selectObject: selected ("Sound", 1)
Copy: "XXXX"
selectObject: "Sound XXXX"
Resample: 44100, 50

# 2) build Euclidean rhythm pattern
dur = 2.0         ; total length of impulse train (s)
n   = 16          ; number of steps
k   = 5           ; number of pulses
step = dur / n

Create empty PointProcess: "pp_euclid", 0, dur
selectObject: "PointProcess pp_euclid"

i = 0
while i < n
    if ((i * k) mod n) < k
        Add point: i * step
    endif
    i = i + 1
endwhile

# 3) convert to impulse sound
To Sound (pulse train): 44100, 1, 0.02, 2000
Rename: "impulse_euclid"
Scale peak: 0.99

# 4) convolve COPY * euclidean impulse
selectObject: "Sound XXXX"
plusObject: "Sound impulse_euclid"
Convolve: "peak 0.99", "zero"
Rename: "result"
Play

# 5) cleanup: keep original + result
selectObject: "Sound XXXX"
plusObject: "PointProcess pp_euclid"
plusObject: "Sound impulse_euclid"
Remove
