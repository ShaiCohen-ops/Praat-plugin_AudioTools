# ============================================================
# Praat AudioTools - convolve_PING-PONG.praat
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

form Bursts and Sparse Taps Convolution
    comment This script creates sparse taps plus clustered bursts
    positive duration_seconds 1.8
    comment Sparse tap times:
    positive tap_1_time 0.15
    positive tap_2_time 1.20
    comment Burst parameters:
    natural number_of_bursts 3
    natural points_per_burst 10
    positive burst_stddev 0.035
    comment (Gaussian spread of burst cluster)
    positive burst_min_time 0.3
    comment (margin from edges)
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

# Create point pattern with sparse taps and bursts
Create empty PointProcess: "pp_bursts", 0, duration_seconds
selectObject: "PointProcess pp_bursts"

# Add sparse taps
Add point: tap_1_time
Add point: tap_2_time

# Add bursts
b = 1
while b <= number_of_bursts
    c = randomUniform(burst_min_time, duration_seconds - burst_min_time)
    i = 1
    while i <= points_per_burst
        u = c + randomGauss(0, burst_stddev)
        if u > 0 and u < duration_seconds
            Add point: u
        endif
        i = i + 1
    endwhile
    b = b + 1
endwhile

# Convert to pulse train
To Sound (pulse train): sampling_frequency, pulse_amplitude, pulse_width, pulse_period
Rename: "impulse_bursts"
Scale peak: 0.99

# Convolve
selectObject: "Sound XXXX"
plusObject: "Sound impulse_bursts"
Convolve: "peak 0.99", "zero"
Rename: originalName$ + "_bursts_taps"

if play_after_processing
    Play
endif

# Cleanup
selectObject: "Sound XXXX"
plusObject: "PointProcess pp_bursts"
plusObject: "Sound impulse_bursts"
Remove

selectObject: "Sound " + originalName$ + "_bursts_taps"