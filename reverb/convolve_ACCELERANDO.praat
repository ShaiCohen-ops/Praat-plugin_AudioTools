# ============================================================
# Praat AudioTools - convolve_ACCELERANDO.praat
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

form Minimal Convolution with Tail
    comment This script convolves sound with fixed-time impulses
    positive tail_duration_seconds 1
    comment Impulse times (in seconds within 1s window):
    positive impulse_time_1 0.10
    positive impulse_time_2 0.20
    positive impulse_time_3 0.50
    comment Pulse train parameters:
    positive sampling_frequency 44100
    positive pulse_amplitude 1
    positive pulse_width 0.05
    positive pulse_period 2000
    comment Output:
    boolean play_after_processing 1
endform

if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

original_sound$ = selected$("Sound")
select Sound 'original_sound$'

original_duration = Get total duration
sampling_rate = Get sample rate
channels = Get number of channels

# Create silent tail
if channels = 2
    Create Sound from formula: "silent_tail", 2, 0, tail_duration_seconds, sampling_rate, "0"
else
    Create Sound from formula: "silent_tail", 1, 0, tail_duration_seconds, sampling_rate, "0"
endif

# Concatenate
select Sound 'original_sound$'
plus Sound silent_tail
Concatenate
Rename: "extended_sound"

# Process
select Sound extended_sound
Copy: "XXXX"
selectObject: "Sound XXXX"
Resample: sampling_frequency, 50

# Create impulses at fixed times
Create empty PointProcess: "IMPPOINTS", 0, 1
selectObject: "PointProcess IMPPOINTS"
Add point: impulse_time_1
Add point: impulse_time_2
Add point: impulse_time_3

# Convert to impulse sound
To Sound (pulse train): sampling_frequency, pulse_amplitude, pulse_width, pulse_period
Rename: "IMPULSE"

# Convolve
selectObject: "Sound XXXX"
plusObject: "Sound IMPULSE"
Convolve: "peak 0.99", "zero"
Rename: original_sound$ + "_convolved"

# Cleanup
selectObject: "Sound XXXX"
plusObject: "PointProcess IMPPOINTS"
plusObject: "Sound IMPULSE"
plusObject: "Sound extended_sound"
plusObject: "Sound silent_tail"
Remove

select Sound 'original_sound$'_convolved

if play_after_processing
    Play
endif