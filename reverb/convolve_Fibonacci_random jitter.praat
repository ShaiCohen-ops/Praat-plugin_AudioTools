# ============================================================
# Praat AudioTools - convolve_Fibonacci_random jitter.praat
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

form Fibonacci Impulse with Jitter Convolution
    comment This script creates Fibonacci-spaced impulses with random jitter
    positive duration_seconds 1.5
    natural number_of_impulses 12
    positive fibonacci_scale_divisor 100.0
    positive jitter_stddev_seconds 0.015
    comment (standard deviation of Gaussian jitter)
    comment Pulse train parameters:
    positive sampling_frequency 44100
    positive pulse_amplitude 1
    positive pulse_width 0.05
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

# Create Fibonacci-spaced point pattern with jitter
Create empty PointProcess: "IMPPOINTS", 0, duration_seconds
selectObject: "PointProcess IMPPOINTS"

fib1 = 1
fib2 = 1

for i from 1 to number_of_impulses
    t = (fib1 / fibonacci_scale_divisor) * duration_seconds
    # Add Gaussian jitter
    t = t + randomGauss(0, jitter_stddev_seconds)
    if t > 0 and t < duration_seconds
        Add point: t
    endif
    fibTemp = fib1 + fib2
    fib1 = fib2
    fib2 = fibTemp
endfor

# Convert to pulse train
To Sound (pulse train): sampling_frequency, pulse_amplitude, pulse_width, pulse_period
Rename: "IMPULSE"
Scale peak: 0.99

# Convolve
selectObject: "Sound XXXX"
plusObject: "Sound IMPULSE"
Convolve: "peak 0.99", "zero"
Rename: originalName$ + "_fibonacci_jitter"

if play_after_processing
    Play
endif

# Cleanup
selectObject: "Sound XXXX"
plusObject: "PointProcess IMPPOINTS"
plusObject: "Sound IMPULSE"
Remove

selectObject: "Sound " + originalName$ + "_fibonacci_jitter"