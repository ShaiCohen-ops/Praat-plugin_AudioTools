# CREATIVE STEREO IMPULSES (Fibonacci + jitter) → convolve with a COPY

# 1) need a selected Sound
if numberOfSelected ("Sound") < 1
    exitScript: "Select a Sound in the Objects window first."
endif

# copy the selection to "XXXX"
selectObject: selected ("Sound", 1)
Copy: "XXXX"

# resample copy to 44.1 kHz if needed
selectObject: "Sound XXXX"
Resample: 44100, 50

# 2) make LEFT pattern
dur = 1.5
Create empty PointProcess: "PP_LEFT", 0, dur
selectObject: "PointProcess PP_LEFT"

fib1 = 1
fib2 = 1
jitter = 0.010    ; jitter in seconds

for i from 1 to 12
    t = (fib1 / 100.0) * dur + randomGauss (0, jitter)
    if t > 0 and t < dur
        Add point: t
    endif
    fibTemp = fib1 + fib2
    fib1 = fib2
    fib2 = fibTemp
endfor

# 3) make RIGHT pattern (offset Fibonacci, more jitter)
Create empty PointProcess: "PP_RIGHT", 0, dur
selectObject: "PointProcess PP_RIGHT"

fib1 = 2
fib2 = 3
jitter = 0.020

for i from 1 to 12
    t = (fib1 / 120.0) * dur + randomGauss (0, jitter)
    if t > 0 and t < dur
        Add point: t
    endif
    fibTemp = fib1 + fib2
    fib1 = fib2
    fib2 = fibTemp
endfor

# 4) convert each to mono impulse Sound
selectObject: "PointProcess PP_LEFT"
To Sound (pulse train): 44100, 1, 0.05, 2000
Rename: "IMP_LEFT"
Scale peak: 0.99

selectObject: "PointProcess PP_RIGHT"
To Sound (pulse train): 44100, 1, 0.05, 2000
Rename: "IMP_RIGHT"
Scale peak: 0.99

# 5) combine into stereo Sound
selectObject: "Sound IMP_LEFT"
plusObject: "Sound IMP_RIGHT"
Combine to stereo
Rename: "IMPULSE_STEREO"

# 6) convolve COPY * stereo impulse
selectObject: "Sound XXXX"
plusObject: "Sound IMPULSE_STEREO"
Convolve: "peak 0.99", "zero"
Rename: "RESULT"

# listen
Play

# 7) cleanup: keep original + RESULT
selectObject: "Sound XXXX"
plusObject: "PointProcess PP_LEFT"
plusObject: "PointProcess PP_RIGHT"
plusObject: "Sound IMP_LEFT"
plusObject: "Sound IMP_RIGHT"
plusObject: "Sound IMPULSE_STEREO"
Remove
