# ============================================================
# Praat AudioTools - convolve_RANDOM WALK.praat
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

form Random Walk Density Convolution
    comment This script creates impulses with randomly evolving spacing
    positive duration_seconds 1.8
    positive first_pulse_time 0.10
    positive initial_gap 0.18
    positive gap_variation_stddev 0.015
    positive minimum_gap 0.020
    positive maximum_gap 0.400
    natural maximum_pulses 200
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
Convert to mono

# Create random walk point pattern
Create empty PointProcess: "pp_walk", 0, duration_seconds
selectObject: "PointProcess pp_walk"

t = first_pulse_time
gap = initial_gap
i = 0

while (t < duration_seconds) and (i < maximum_pulses)
    Add point: t
    gap = gap + randomGauss(0, gap_variation_stddev)
    if gap < minimum_gap
        gap = minimum_gap
    endif
    if gap > maximum_gap
        gap = maximum_gap
    endif
    t = t + gap
    i = i + 1
endwhile

# Convert to pulse train
To Sound (pulse train): sampling_frequency, pulse_amplitude, pulse_width, pulse_period
Rename: "impulse_walk"
Scale peak: 0.99

# Convolve
selectObject: "Sound XXXX"
plusObject: "Sound impulse_walk"
Convolve: "peak 0.99", "zero"
Rename: originalName$ + "_random_walk"

if play_after_processing
    Play
endif

# Cleanup
selectObject: "Sound XXXX"
plusObject: "PointProcess pp_walk"
plusObject: "Sound impulse_walk"
Remove

selectObject: "Sound " + originalName$ + "_random_walk"