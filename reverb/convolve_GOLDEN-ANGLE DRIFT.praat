# ============================================================
# Praat AudioTools - convolve_GOLDEN-ANGLE DRIFT.praat
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

form Golden-Angle Drift Convolution
    comment This script creates impulses using golden ratio spacing
    positive duration_seconds 1.8
    natural number_of_impulses 24
    positive margin_seconds 0.10
    comment (empty space at start/end)
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

# Create golden-angle point pattern
Create empty PointProcess: "pp_golden", 0, duration_seconds
selectObject: "PointProcess pp_golden"

phi = (sqrt(5) - 1) / 2

i = 1
while i <= number_of_impulses
    u = (i * phi) - floor(i * phi)
    t = margin_seconds + u * (duration_seconds - 2 * margin_seconds)
    if t > 0 and t < duration_seconds
        Add point: t
    endif
    i = i + 1
endwhile

# Convert to pulse train
To Sound (pulse train): sampling_frequency, pulse_amplitude, pulse_width, pulse_period
Rename: "impulse_golden"
Scale peak: 0.99

# Convolve
selectObject: "Sound XXXX"
plusObject: "Sound impulse_golden"
Convolve: "peak 0.99", "zero"
Rename: originalName$ + "_golden_angle"

if play_after_processing
    Play
endif

# Cleanup
selectObject: "Sound XXXX"
plusObject: "PointProcess pp_golden"
plusObject: "Sound impulse_golden"
Remove

selectObject: "Sound " + originalName$ + "_golden_angle"