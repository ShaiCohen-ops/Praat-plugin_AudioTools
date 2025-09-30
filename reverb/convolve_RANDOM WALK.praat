# RANDOM WALK DENSITY → convolve with a COPY of the selected sound

if numberOfSelected ("Sound") < 1
    exitScript: "Select a Sound in the Objects window first."
endif

selectObject: selected ("Sound", 1)
Copy: "XXXX"
selectObject: "Sound XXXX"
Resample: 44100, 50
Convert to mono

dur = 1.8
Create empty PointProcess: "pp_walk", 0, dur
selectObject: "PointProcess pp_walk"

t0       = 0.10
gap      = 0.18
sigma    = 0.015
min_gap  = 0.020
max_gap  = 0.400
max_pulses = 200

t = t0
i = 0
while (t < dur) and (i < max_pulses)
    Add point: t
    gap = gap + randomGauss (0, sigma)
    if gap < min_gap
        gap = min_gap
    endif
    if gap > max_gap
        gap = max_gap
    endif
    t = t + gap
    i = i + 1
endwhile

To Sound (pulse train): 44100, 1, 0.02, 2000
Rename: "impulse_walk"
Scale peak: 0.99

selectObject: "Sound XXXX"
plusObject: "Sound impulse_walk"
Convolve: "peak 0.99", "zero"
Rename: "result"
Play

selectObject: "Sound XXXX"
plusObject: "PointProcess pp_walk"
plusObject: "Sound impulse_walk"
Remove
