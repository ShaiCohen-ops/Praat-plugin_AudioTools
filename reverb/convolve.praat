# ============================================================
# Praat AudioTools - convolve.praat
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

form Stereo Ping-Pong Impulses
    comment This script creates alternating left/right impulse train convolution
    positive duration_seconds 1.6
    positive step_interval 0.22
    positive jitter_amount 0.01
    positive initial_delay 0.10
    comment Pulse train parameters:
    positive sampling_frequency 44100
    positive pulse_amplitude 1
    positive pulse_width 0.03
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
Convert to mono

# Create left channel point process (starts at initial_delay)
Create empty PointProcess: "pp_l", 0, duration_seconds
selectObject: "PointProcess pp_l"
t = initial_delay
while t < duration_seconds
    u = t + randomUniform(-jitter_amount, jitter_amount)
    if u > 0 and u < duration_seconds
        Add point: u
    endif
    t = t + 2 * step_interval
endwhile

# Create right channel point process (offset by step_interval)
Create empty PointProcess: "pp_r", 0, duration_seconds
selectObject: "PointProcess pp_r"
t = initial_delay + step_interval
while t < duration_seconds
    u = t + randomUniform(-jitter_amount, jitter_amount)
    if u > 0 and u < duration_seconds
        Add point: u
    endif
    t = t + 2 * step_interval
endwhile

# Convert to pulse trains
selectObject: "PointProcess pp_l"
To Sound (pulse train): sampling_frequency, pulse_amplitude, pulse_width, pulse_period
Rename: "imp_l"
Scale peak: 0.99

selectObject: "PointProcess pp_r"
To Sound (pulse train): sampling_frequency, pulse_amplitude, pulse_width, pulse_period
Rename: "imp_r"
Scale peak: 0.99

# Convolve left
selectObject: "Sound XXXX"
plusObject: "Sound imp_l"
Convolve: "peak 0.99", "zero"
Rename: "res_l"

# Convolve right
selectObject: "Sound XXXX"
plusObject: "Sound imp_r"
Convolve: "peak 0.99", "zero"
Rename: "res_r"

# Combine to stereo
selectObject: "Sound res_l"
plusObject: "Sound res_r"
Combine to stereo
Rename: originalName$ + "_ping_pong"
Scale peak: 0.99

if play_after_processing
    Play
endif

# Cleanup
selectObject: "Sound XXXX"
plusObject: "PointProcess pp_l"
plusObject: "PointProcess pp_r"
plusObject: "Sound imp_l"
plusObject: "Sound imp_r"
plusObject: "Sound res_l"
plusObject: "Sound res_r"
Remove

selectObject: "Sound " + originalName$ + "_ping_pong"