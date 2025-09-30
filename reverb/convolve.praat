# STEREO PING-PONG IMPULSES → convolve with a COPY of the selected sound

if numberOfSelected ("Sound") < 1
    exitScript: "Select a Sound in the Objects window first."
endif

selectObject: selected ("Sound", 1)
Copy: "XXXX"
selectObject: "Sound XXXX"
Resample: 44100, 50
Convert to mono

dur  = 1.6
step = 0.22
jit  = 0.01

Create empty PointProcess: "pp_l", 0, dur
selectObject: "PointProcess pp_l"
t = 0.10
while t < dur
    u = t + randomUniform (-jit, jit)
    if u > 0 and u < dur
        Add point: u
    endif
    t = t + 2 * step
endwhile

Create empty PointProcess: "pp_r", 0, dur
selectObject: "PointProcess pp_r"
t = 0.10 + step
while t < dur
    u = t + randomUniform (-jit, jit)
    if u > 0 and u < dur
        Add point: u
    endif
    t = t + 2 * step
endwhile

selectObject: "PointProcess pp_l"
To Sound (pulse train): 44100, 1, 0.03, 2000
Rename: "imp_l"
Scale peak: 0.99

selectObject: "PointProcess pp_r"
To Sound (pulse train): 44100, 1, 0.03, 2000
Rename: "imp_r"
Scale peak: 0.99

selectObject: "Sound XXXX"
plusObject: "Sound imp_l"
Convolve: "peak 0.99", "zero"
Rename: "res_l"

selectObject: "Sound XXXX"
plusObject: "Sound imp_r"
Convolve: "peak 0.99", "zero"
Rename: "res_r"

selectObject: "Sound res_l"
plusObject: "Sound res_r"
Combine to stereo
Rename: "result"
Scale peak: 0.99
Play

selectObject: "Sound XXXX"
plusObject: "PointProcess pp_l"
plusObject: "PointProcess pp_r"
plusObject: "Sound imp_l"
plusObject: "Sound imp_r"
plusObject: "Sound res_l"
plusObject: "Sound res_r"
Remove
