# MINIMAL: make fixed impulses → convolve with a COPY, keep original

# need a selected Sound
if numberOfSelected ("Sound") < 1
    exitScript: "Select a Sound in the Objects window first."
endif

# copy the selection to "XXXX"
selectObject: selected ("Sound", 1)
Copy: "XXXX"

# resample copy to 44.1 kHz if needed
selectObject: "Sound XXXX"
Resample: 44100, 50

# make a few impulses at fixed times (0.10, 0.20, 0.50 s) in a 1 s window
Create empty PointProcess: "IMPPOINTS", 0, 1
selectObject: "PointProcess IMPPOINTS"
Add point: 0.10
Add point: 0.20
Add point: 0.50

# convert to an impulse Sound (4-argument form)
To Sound (pulse train): 44100, 1, 0.05, 2000
Rename: "IMPULSE"

# convolve COPY * IMPULSE
selectObject: "Sound XXXX"
plusObject: "Sound IMPULSE"
Convolve: "peak 0.99", "zero"
Rename: "RESULT"

# listen
Play

# cleanup: remove only temp objects, keep original + RESULT
selectObject: "Sound XXXX"
plusObject: "PointProcess IMPPOINTS"
plusObject: "Sound IMPULSE"
Remove
