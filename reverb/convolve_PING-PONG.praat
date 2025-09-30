# BURSTS + SPARSE TAPS → convolve with a COPY of the selected sound

if numberOfSelected ("Sound") < 1
    exitScript: "Select a Sound in the Objects window first."
endif

selectObject: selected ("Sound", 1)
Copy: "XXXX"
selectObject: "Sound XXXX"
Resample: 44100, 50

dur = 1.8
Create empty PointProcess: "pp_bursts", 0, dur
selectObject: "PointProcess pp_bursts"

# sparse taps
Add point: 0.15
Add point: 1.20

# bursts
nbursts = 3
points_per_burst = 10
burst_sigma = 0.035

b = 1
while b <= nbursts
    c = randomUniform (0.3, dur - 0.3)
    i = 1
    while i <= points_per_burst
        u = c + randomGauss (0, burst_sigma)
        if u > 0 and u < dur
            Add point: u
        endif
        i = i + 1
    endwhile
    b = b + 1
endwhile

To Sound (pulse train): 44100, 1, 0.02, 2000
Rename: "impulse_bursts"
Scale peak: 0.99

selectObject: "Sound XXXX"
plusObject: "Sound impulse_bursts"
Convolve: "peak 0.99", "zero"
Rename: "result"
Play

selectObject: "Sound XXXX"
plusObject: "PointProcess pp_bursts"
plusObject: "Sound impulse_bursts"
Remove
