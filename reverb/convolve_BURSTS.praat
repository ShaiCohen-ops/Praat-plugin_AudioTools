# ACCELERANDO (safe, finite pulses) → convolve with a COPY

if numberOfSelected ("Sound") < 1
    exitScript: "Select a Sound in the Objects window first."
endif

selectObject: selected ("Sound", 1)
Copy: "XXXX"
selectObject: "Sound XXXX"
Resample: 44100, 50

dur    = 2.0      ; total impulse-train length
t0     = 0.10     ; first hit time
npulse = 24       ; total number of impulses (finite, avoids freeze)
ratio  = 0.85     ; gap shrink factor (0<ratio<1, lower = faster accel)

remain = dur - t0
if remain <= 0
    exitScript: "dur must be greater than t0."
endif

den = 1 - ratio^npulse
if den = 0
    exitScript: "Choose ratio so that 1 - ratio^npulse ≠ 0."
endif

g0 = remain * (1 - ratio) / den

Create empty PointProcess: "pp_accel", 0, dur
selectObject: "PointProcess pp_accel"

t = t0
i = 1
while i <= npulse and t < dur
    Add point: t
    gap = g0 * ratio^(i - 1)
    t = t + gap
    i = i + 1
endwhile

To Sound (pulse train): 44100, 1, 0.02, 2000
Rename: "impulse_accel"
Scale peak: 0.99

selectObject: "Sound XXXX"
plusObject: "Sound impulse_accel"
Convolve: "peak 0.99", "zero"
Rename: "result"
Play

selectObject: "Sound XXXX"
plusObject: "PointProcess pp_accel"
plusObject: "Sound impulse_accel"
Remove
