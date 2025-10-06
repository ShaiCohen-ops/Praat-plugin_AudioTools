# ============================================================
# Praat AudioTools - convolve_BOUNCING BALL.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Reverberation or diffusion script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Bouncing Ball Convolution
    comment This script creates bouncing ball physics-based impulse convolution
    positive duration_seconds 1.6
    positive first_bounce_time 0.10
    comment Physics parameters:
    positive gravity 9.81
    positive initial_velocity 3.0
    positive bounce_coefficient 0.60
    comment (energy retention: 0-1, lower = faster decay)
    comment Pulse train parameters:
    positive sampling_frequency 44100
    positive pulse_amplitude 1
    positive pulse_width 0.02
    positive pulse_period 2000
    comment Output:
    boolean play_after_processing 1
endform

if numberOfSelected("Sound") < 1
    exitScript: "Select a Sound in the Objects window first."
endif

selectObject: selected("Sound", 1)
originalName$ = selected$("Sound")
Copy: "XXXX"
selectObject: "Sound XXXX"
Resample: sampling_frequency, 50

# Create bouncing ball point pattern
Create empty PointProcess: "pp_bounce", 0, duration_seconds
selectObject: "PointProcess pp_bounce"

t = first_bounce_time
v = initial_velocity

if t > 0 and t < duration_seconds
    Add point: t
endif

dt = 2 * v / gravity

while t + dt < duration_seconds
    t = t + dt
    Add point: t
    v = bounce_coefficient * v
    dt = 2 * v / gravity
endwhile

# Convert to pulse train
To Sound (pulse train): sampling_frequency, pulse_amplitude, pulse_width, pulse_period
Rename: "impulse_bounce"
Scale peak: 0.99

# Convolve
selectObject: "Sound XXXX"
plusObject: "Sound impulse_bounce"
Convolve: "peak 0.99", "zero"
Rename: originalName$ + "_bouncing_ball"

if play_after_processing
    Play
endif

# Cleanup
selectObject: "Sound XXXX"
plusObject: "PointProcess pp_bounce"
plusObject: "Sound impulse_bounce"
Remove

selectObject: "Sound " + originalName$ + "_bouncing_ball"