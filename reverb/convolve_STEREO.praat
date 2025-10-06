# ============================================================
# Praat AudioTools - convolve_STEREO.praat
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

form Stereo Fibonacci Impulses Convolution
    comment This script creates stereo Fibonacci patterns with different jitter
    positive duration_seconds 1.5
    natural number_of_impulses 12
    comment Left channel:
    positive left_fib_start_1 1
    positive left_fib_start_2 1
    positive left_scale_divisor 100.0
    positive left_jitter_stddev 0.010
    comment Right channel:
    positive right_fib_start_1 2
    positive right_fib_start_2 3
    positive right_scale_divisor 120.0
    positive right_jitter_stddev 0.020
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

# Create LEFT pattern
Create empty PointProcess: "PP_LEFT", 0, duration_seconds
selectObject: "PointProcess PP_LEFT"
fib1 = left_fib_start_1
fib2 = left_fib_start_2
for i from 1 to number_of_impulses
    t = (fib1 / left_scale_divisor) * duration_seconds + randomGauss(0, left_jitter_stddev)
    if t > 0 and t < duration_seconds
        Add point: t
    endif
    fibTemp = fib1 + fib2
    fib1 = fib2
    fib2 = fibTemp
endfor

# Create RIGHT pattern
Create empty PointProcess: "PP_RIGHT", 0, duration_seconds
selectObject: "PointProcess PP_RIGHT"
fib1 = right_fib_start_1
fib2 = right_fib_start_2
for i from 1 to number_of_impulses
    t = (fib1 / right_scale_divisor) * duration_seconds + randomGauss(0, right_jitter_stddev)
    if t > 0 and t < duration_seconds
        Add point: t
    endif
    fibTemp = fib1 + fib2
    fib1 = fib2
    fib2 = fibTemp
endfor

# Convert to pulse trains
selectObject: "PointProcess PP_LEFT"
To Sound (pulse train): sampling_frequency, pulse_amplitude, pulse_width, pulse_period
Rename: "IMP_LEFT"
Scale peak: 0.99

selectObject: "PointProcess PP_RIGHT"
To Sound (pulse train): sampling_frequency, pulse_amplitude, pulse_width, pulse_period
Rename: "IMP_RIGHT"
Scale peak: 0.99

# Combine to stereo
selectObject: "Sound IMP_LEFT"
plusObject: "Sound IMP_RIGHT"
Combine to stereo
Rename: "IMPULSE_STEREO"

# Convolve
selectObject: "Sound XXXX"
plusObject: "Sound IMPULSE_STEREO"
Convolve: "peak 0.99", "zero"
Rename: originalName$ + "_stereo_fibonacci"

if play_after_processing
    Play
endif

# Cleanup
selectObject: "Sound XXXX"
plusObject: "PointProcess PP_LEFT"
plusObject: "PointProcess PP_RIGHT"
plusObject: "Sound IMP_LEFT"
plusObject: "Sound IMP_RIGHT"
plusObject: "Sound IMPULSE_STEREO"
Remove

selectObject: "Sound " + originalName$ + "_stereo_fibonacci"