# ============================================================
# Praat AudioTools - convolve_SWING.praat
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

form Tempo Grid with Swing Convolution
    comment This script creates swung rhythm impulse convolution
    positive duration_seconds 2.0
    positive tempo_bpm 120
    positive swing_delay_seconds 0.06
    comment (delay applied to every 2nd beat)
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

# Calculate beat duration
beat = 60 / tempo_bpm

# Create tempo grid with swing
Create empty PointProcess: "pp_swing", 0, duration_seconds
selectObject: "PointProcess pp_swing"

t = beat
i = 1

while t < duration_seconds
    if (i mod 2) = 0
        Add point: t + swing_delay_seconds
    else
        Add point: t
    endif
    t = t + beat
    i = i + 1
endwhile

# Convert to pulse train
To Sound (pulse train): sampling_frequency, pulse_amplitude, pulse_width, pulse_period
Rename: "impulse_swing"
Scale peak: 0.99

# Convolve
selectObject: "Sound XXXX"
plusObject: "Sound impulse_swing"
Convolve: "peak 0.99", "zero"
Rename: originalName$ + "_swing"

if play_after_processing
    Play
endif

# Cleanup
selectObject: "Sound XXXX"
plusObject: "PointProcess pp_swing"
plusObject: "Sound impulse_swing"
Remove

selectObject: "Sound " + originalName$ + "_swing"