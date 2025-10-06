# ============================================================
# Praat AudioTools - convolve_BURSTS.praat
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

form Accelerando Convolution
    comment This script creates accelerating impulse train convolution
    positive duration_seconds 2.0
    positive first_hit_time 0.10
    natural number_of_pulses 24
    positive gap_shrink_ratio 0.85
    comment (0 < ratio < 1, lower = faster acceleration)
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

# Calculate initial gap
remain = duration_seconds - first_hit_time
if remain <= 0
    exitScript: "Duration must be greater than first hit time."
endif

den = 1 - gap_shrink_ratio^number_of_pulses
if den = 0
    exitScript: "Choose ratio so that 1 - ratio^npulse ≠ 0."
endif

g0 = remain * (1 - gap_shrink_ratio) / den

# Create accelerating point process
Create empty PointProcess: "pp_accel", 0, duration_seconds
selectObject: "PointProcess pp_accel"
t = first_hit_time
i = 1
while i <= number_of_pulses and t < duration_seconds
    Add point: t
    gap = g0 * gap_shrink_ratio^(i - 1)
    t = t + gap
    i = i + 1
endwhile

# Convert to pulse train
To Sound (pulse train): sampling_frequency, pulse_amplitude, pulse_width, pulse_period
Rename: "impulse_accel"
Scale peak: 0.99

# Convolve
selectObject: "Sound XXXX"
plusObject: "Sound impulse_accel"
Convolve: "peak 0.99", "zero"
Rename: originalName$ + "_accelerando"

if play_after_processing
    Play
endif

# Cleanup
selectObject: "Sound XXXX"
plusObject: "PointProcess pp_accel"
plusObject: "Sound impulse_accel"
Remove

selectObject: "Sound " + originalName$ + "_accelerando"