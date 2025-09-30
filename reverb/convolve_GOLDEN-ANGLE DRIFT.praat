# GOLDEN-ANGLE DRIFT → convolve with a COPY of the selected sound

if numberOfSelected ("Sound") < 1
    exitScript: "Select a Sound in the Objects window first."
endif

selectObject: selected ("Sound", 1)
Copy: "XXXX"
selectObject: "Sound XXXX"
Resample: 44100, 50
Convert to mono

dur = 1.8
n   = 24
margin = 0.10

Create empty PointProcess: "pp_golden", 0, dur
selectObject: "PointProcess pp_golden"

phi = (sqrt(5) - 1) / 2
i = 1
while i <= n
    u = (i * phi) - floor (i * phi)
    t = margin + u * (dur - 2 * margin)
    if t > 0 and t < dur
        Add point: t
    endif
    i = i + 1
endwhile

To Sound (pulse train): 44100, 1, 0.02, 2000
Rename: "impulse_golden"
Scale peak: 0.99

selectObject: "Sound XXXX"
plusObject: "Sound impulse_golden"
Convolve: "peak 0.99", "zero"
Rename: "result"
Play

selectObject: "Sound XXXX"
plusObject: "PointProcess pp_golden"
plusObject: "Sound impulse_golden"
Remove
