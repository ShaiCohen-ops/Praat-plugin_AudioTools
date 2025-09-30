# TEMPO GRID WITH SWING IMPULSES → convolve with a COPY of the selected sound

# 1) need a selected Sound
if numberOfSelected ("Sound") < 1
    exitScript: "Select a Sound in the Objects window first."
endif

# copy the selection to "XXXX"
selectObject: selected ("Sound", 1)
Copy: "XXXX"
selectObject: "Sound XXXX"
Resample: 44100, 50

# 2) tempo grid with swing
dur = 2.0
bpm = 120
beat = 60 / bpm
swing = 0.06    ; amount of delay for every 2nd beat

Create empty PointProcess: "pp_swing", 0, dur
selectObject: "PointProcess pp_swing"

t = beat
i = 1
while t < dur
    if (i mod 2) = 0
        Add point: t + swing
    else
        Add point: t
    endif
    t = t + beat
    i = i + 1
endwhile

# 3) convert to impulse sound
To Sound (pulse train): 44100, 1, 0.02, 2000
Rename: "impulse_swing"
Scale peak: 0.99

# 4) convolve COPY * swing impulse
selectObject: "Sound XXXX"
plusObject: "Sound impulse_swing"
Convolve: "peak 0.99", "zero"
Rename: "result"
Play

# 5) cleanup: keep original + result
selectObject: "Sound XXXX"
plusObject: "PointProcess pp_swing"
plusObject: "Sound impulse_swing"
Remove
