# ============================================================
# Praat AudioTools - convolve_EUCLIDEAN RHYTHM.praat
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

form Euclidean Rhythm Convolution
    comment This script creates Euclidean rhythm pattern convolution
    positive duration_seconds 2.0
    natural number_of_steps 16
    natural number_of_pulses 5
    comment (pulses distributed evenly across steps)
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

# Build Euclidean rhythm pattern
step = duration_seconds / number_of_steps

Create empty PointProcess: "pp_euclid", 0, duration_seconds
selectObject: "PointProcess pp_euclid"

i = 0
while i < number_of_steps
    if ((i * number_of_pulses) mod number_of_steps) < number_of_pulses
        Add point: i * step
    endif
    i = i + 1
endwhile

# Convert to pulse train
To Sound (pulse train): sampling_frequency, pulse_amplitude, pulse_width, pulse_period
Rename: "impulse_euclid"
Scale peak: 0.99

# Convolve
selectObject: "Sound XXXX"
plusObject: "Sound impulse_euclid"
Convolve: "peak 0.99", "zero"
Rename: originalName$ + "_euclidean"

if play_after_processing
    Play
endif

# Cleanup
selectObject: "Sound XXXX"
plusObject: "PointProcess pp_euclid"
plusObject: "Sound impulse_euclid"
Remove

selectObject: "Sound " + originalName$ + "_euclidean"