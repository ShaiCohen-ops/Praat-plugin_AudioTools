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
    optionmenu Preset: 1
        option "Default (16 steps, 5 pulses)"
        option "4-on-16 (straight 16ths)"
        option "3-on-8 (hemiola)"
        option "7-on-12 (Balkan-ish)"
        option "Dense 9-on-16"
        option "Custom"
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

# Apply preset values if not Custom
if preset = 1
    ; Default (16, 5) -> keep form defaults
elsif preset = 2
    # 4-on-16 (straight 16ths)
    number_of_steps = 16
    number_of_pulses = 4
    pulse_width = 0.02
elsif preset = 3
    # 3-on-8 (hemiola)
    number_of_steps = 8
    number_of_pulses = 3
    pulse_width = 0.02
elsif preset = 4
    # 7-on-12 (Balkan-ish)
    number_of_steps = 12
    number_of_pulses = 7
    pulse_width = 0.018
elsif preset = 5
    # Dense 9-on-16
    number_of_steps = 16
    number_of_pulses = 9
    pulse_width = 0.018
endif

# --- Safety: need a selected Sound ---
if numberOfSelected("Sound") < 1
    exitScript: "Select a Sound in the Objects window first."
endif

# --- Sanity checks ---
if number_of_pulses > number_of_steps
    exitScript: "number_of_pulses must be <= number_of_steps."
endif
if number_of_steps < 1 or number_of_pulses < 1
    exitScript: "number_of_steps and number_of_pulses must be >= 1."
endif

# --- Prep source (keep original untouched) ---
selectObject: selected("Sound", 1)
originalName$ = selected$("Sound")

# Working copies with explicit names to avoid *_44100 leftovers
Copy: "XXXX_src"
selectObject: "Sound XXXX_src"
Resample: sampling_frequency, 50
Rename: "XXXX_resampled"

# --- Build Euclidean rhythm pattern ---
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

# --- Convert to pulse train ---
To Sound (pulse train): sampling_frequency, pulse_amplitude, pulse_width, pulse_period
Rename: "impulse_euclid"
Scale peak: 0.99

# --- Convolve ---
selectObject: "Sound XXXX_resampled"
plusObject: "Sound impulse_euclid"
Convolve: "peak 0.99", "zero"
Rename: originalName$ + "_euclidean"

if play_after_processing
    Play
endif

# --- Cleanup (keep original + result) ---
selectObject: "Sound XXXX_src"
plusObject: "Sound XXXX_resampled"
plusObject: "PointProcess pp_euclid"
plusObject: "Sound impulse_euclid"
Remove

# Reselect final result (original remains)
selectObject: "Sound " + originalName$ + "_euclidean"
