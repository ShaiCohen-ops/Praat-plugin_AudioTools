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
    optionmenu Preset: 1
        option "Default (balanced)"
        option "High Bounce (elastic)"
        option "Low Bounce (thuds)"
        option "Rapid Small Bounces"
        option "Custom"
    comment This script creates bouncing ball physics-based impulse convolution
    positive duration_seconds 1.6
    positive first_bounce_time 0.10
    comment Physics parameters:
    positive gravity 9.81
    positive initial_velocity 3.0
    positive bounce_coefficient 0.60
    comment (energy retention: 0-1, lower = faster decay)
    comment Safety limits:
    natural max_bounces 400
    positive min_bounce_interval 0.001
    comment Pulse train parameters:
    positive sampling_frequency 44100
    positive pulse_amplitude 1
    positive pulse_width 0.02
    positive pulse_period 2000
    comment Output:
    boolean play_after_processing 1
endform

# Apply preset values if not Custom
if preset = 1
    ; Default (balanced) -> keep form defaults
elsif preset = 2
    # High Bounce (elastic): more retained energy, slightly faster first hit
    first_bounce_time = 0.08
    bounce_coefficient = 0.8
    initial_velocity = 3.2
    gravity = 9.81
    pulse_width = 0.018
elsif preset = 3
    # Low Bounce (thuds): energy dies quickly, wider pulses
    first_bounce_time = 0.12
    bounce_coefficient = 0.45
    initial_velocity = 2.6
    gravity = 9.81
    pulse_width = 0.03
    # safety: allow early stop if intervals get tiny
    max_bounces = 400
    min_bounce_interval = 0.001
elsif preset = 4
    # Rapid Small Bounces: quick successive taps, tighter pulses
    first_bounce_time = 0.06
    bounce_coefficient = 0.65
    initial_velocity = 2.2
    gravity = 12.0
    pulse_width = 0.015
endif

# --- Safety: need a selected Sound ---
if numberOfSelected("Sound") < 1
    exitScript: "Select a Sound in the Objects window first."
endif

# --- Prep source (keep original untouched) ---
selectObject: selected("Sound", 1)
originalName$ = selected$("Sound")

# Working copies with explicit names to avoid *_44100 leftovers
Copy: "XXXX_src"
selectObject: "Sound XXXX_src"
Resample: sampling_frequency, 50
Rename: "XXXX_resampled"

# --- Create bouncing ball point pattern ---
Create empty PointProcess: "pp_bounce", 0, duration_seconds
selectObject: "PointProcess pp_bounce"

t  = first_bounce_time
v  = initial_velocity
eps = min_bounce_interval
count = 0

# add first bounce if in range
if t > 0 and t < duration_seconds
    Add point: t
endif

dt = 2 * v / gravity

# SAFE loop: stop if next time exceeds duration, intervals too small, or too many bounces
while (t + dt < duration_seconds) and (dt >= eps) and (count < max_bounces)
    t = t + dt
    Add point: t
    v  = bounce_coefficient * v
    dt = 2 * v / gravity
    count = count + 1
endwhile

# --- Convert to pulse train ---
To Sound (pulse train): sampling_frequency, pulse_amplitude, pulse_width, pulse_period
Rename: "impulse_bounce"
Scale peak: 0.99

# --- Convolve ---
selectObject: "Sound XXXX_resampled"
plusObject: "Sound impulse_bounce"
Convolve: "peak 0.99", "zero"
Rename: originalName$ + "_bouncing_ball"

if play_after_processing
    Play
endif

# --- Cleanup (keep original + result) ---
selectObject: "Sound XXXX_src"
plusObject: "Sound XXXX_resampled"
plusObject: "PointProcess pp_bounce"
plusObject: "Sound impulse_bounce"
Remove

# Reselect final result (original remains)
selectObject: "Sound " + originalName$ + "_bouncing_ball"
