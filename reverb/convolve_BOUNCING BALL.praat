# BOUNCING BALL IMPULSES → convolve with a COPY of the selected sound (no Formula)

# 1) need a selected Sound
if numberOfSelected ("Sound") < 1
    exitScript: "Select a Sound in the Objects window first."
endif

# copy selection to "XXXX" and resample
selectObject: selected ("Sound", 1)
Copy: "XXXX"
selectObject: "Sound XXXX"
Resample: 44100, 50

# 2) bouncing-ball point pattern
dur   = 1.6
Create empty PointProcess: "pp_bounce", 0, dur
selectObject: "PointProcess pp_bounce"

g     = 9.81
v0    = 3.0
coef  = 0.60
t0    = 0.10
t     = t0
v     = v0

if t > 0 and t < dur
    Add point: t
endif

dt = 2 * v / g
while t + dt < dur
    t  = t + dt
    Add point: t
    v  = coef * v
    dt = 2 * v / g
endwhile

# 3) convert to impulse sound (narrow pulses), keep sane peak
To Sound (pulse train): 44100, 1, 0.02, 2000
Rename: "impulse_bounce"
Scale peak: 0.99

# 4) convolve COPY * bouncing-ball impulse
selectObject: "Sound XXXX"
plusObject:   "Sound impulse_bounce"
Convolve: "peak 0.99", "zero"
Rename: "result"
Play

# 5) cleanup: keep original + result, remove temps
selectObject: "Sound XXXX"
plusObject:   "PointProcess pp_bounce"
plusObject:   "Sound impulse_bounce"
Remove
