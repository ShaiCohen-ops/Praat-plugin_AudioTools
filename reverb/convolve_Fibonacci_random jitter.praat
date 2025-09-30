# CREATIVE IMPULSES with Fibonacci spacing + random jitter → convolve with a COPY

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

# 2) make a creative point pattern using Fibonacci spacing + jitter
dur = 1.5    ; total impulse train duration
Create empty PointProcess: "IMPPOINTS", 0, dur
selectObject: "PointProcess IMPPOINTS"

fib1 = 1
fib2 = 1
jitter = 0.015    ; seconds of random jitter (stddev)

for i from 1 to 12   ; number of impulses to add
    t = (fib1 / 100.0) * dur
    # add jitter
    t = t + randomGauss (0, jitter)
    if t > 0 and t < dur
        Add point: t
    endif
    fibTemp = fib1 + fib2
    fib1 = fib2
    fib2 = fibTemp
endfor

# 3) convert to an impulse Sound
To Sound (pulse train): 44100, 1, 0.05, 2000
Rename: "IMPULSE"
Scale peak: 0.99

# 4) convolve COPY * IMPULSE
selectObject: "Sound XXXX"
plusObject: "Sound IMPULSE"
Convolve: "peak 0.99", "zero"
Rename: "RESULT"

# listen
Play

# 5) cleanup: remove temp objects, keep original + RESULT
selectObject: "Sound XXXX"
plusObject: "PointProcess IMPPOINTS"
plusObject: "Sound IMPULSE"
Remove
