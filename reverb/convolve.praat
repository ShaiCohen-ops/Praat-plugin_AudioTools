# ============================================================
# Praat AudioTools - convolve.praat
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

form Stereo Ping-Pong Impulses
    optionmenu Preset: 1
        option "Default (balanced)"
        option "Tight Ping-Pong"
        option "Wide & Slow"
        option "Rapid Micro-Taps"
        option "Offbeat Start"
        option "Custom"
    comment This script creates alternating left/right impulse train convolution
    positive duration_seconds 1.6
    positive step_interval 0.22
    positive jitter_amount 0.01
    positive initial_delay 0.10
    comment Pulse train parameters:
    positive sampling_frequency 44100
    positive pulse_amplitude 1
    positive pulse_width 0.03
    positive pulse_period 2000
    comment Output:
    boolean play_after_processing 1
endform

# Apply preset values if not Custom
if preset = 1
    duration_seconds = 1.6
    step_interval = 0.22
    jitter_amount = 0.01
    initial_delay = 0.10
    sampling_frequency = 44100
    pulse_amplitude = 1
    pulse_width = 0.03
    pulse_period = 2000
    play_after_processing = 1
elsif preset = 2
    duration_seconds = 1.0
    step_interval = 0.15
    jitter_amount = 0.005
    initial_delay = 0.08
    sampling_frequency = 44100
    pulse_amplitude = 1.0
    pulse_width = 0.02
    pulse_period = 1500
    play_after_processing = 1
elsif preset = 3
    duration_seconds = 2.5
    step_interval = 0.35
    jitter_amount = 0.012
    initial_delay = 0.12
    sampling_frequency = 44100
    pulse_amplitude = 1.1
    pulse_width = 0.04
    pulse_period = 2600
    play_after_processing = 1
elsif preset = 4
    duration_seconds = 1.2
    step_interval = 0.08
    jitter_amount = 0.003
    initial_delay = 0.05
    sampling_frequency = 44100
    pulse_amplitude = 0.9
    pulse_width = 0.015
    pulse_period = 1200
    play_after_processing = 1
elsif preset = 5
    duration_seconds = 1.8
    step_interval = 0.22
    jitter_amount = 0.02
    initial_delay = 0.17
    sampling_frequency = 48000
    pulse_amplitude = 1.0
    pulse_width = 0.03
    pulse_period = 2000
    play_after_processing = 1
endif

# --- Safety: require a selected Sound ---
if numberOfSelected("Sound") < 1
    exitScript: "Select a Sound in the Objects window first."
endif

# --- Prep source (keep original untouched) ---
selectObject: selected("Sound", 1)
originalName$ = selected$("Sound")

# Working copies with explicit names to avoid auto-suffix leftovers
Copy: "XXXX_src"
selectObject: "Sound XXXX_src"
Resample: sampling_frequency, 50
Rename: "XXXX_resampled"
Convert to mono
Rename: "XXXX_mono"

# --- Build ping-pong point processes ---
# Left (starts at initial_delay)
Create empty PointProcess: "pp_l", 0, duration_seconds
selectObject: "PointProcess pp_l"
t = initial_delay
while t < duration_seconds
    u = t + randomUniform(-jitter_amount, jitter_amount)
    if u > 0 and u < duration_seconds
        Add point: u
    endif
    t = t + 2 * step_interval
endwhile

# Right (offset by step_interval)
Create empty PointProcess: "pp_r", 0, duration_seconds
selectObject: "PointProcess pp_r"
t = initial_delay + step_interval
while t < duration_seconds
    u = t + randomUniform(-jitter_amount, jitter_amount)
    if u > 0 and u < duration_seconds
        Add point: u
    endif
    t = t + 2 * step_interval
endwhile

# --- Convert to pulse trains ---
selectObject: "PointProcess pp_l"
To Sound (pulse train): sampling_frequency, pulse_amplitude, pulse_width, pulse_period
Rename: "imp_l"
Scale peak: 0.99

selectObject: "PointProcess pp_r"
To Sound (pulse train): sampling_frequency, pulse_amplitude, pulse_width, pulse_period
Rename: "imp_r"
Scale peak: 0.99

# --- Convolve with source copy ---
selectObject: "Sound XXXX_mono"
plusObject: "Sound imp_l"
Convolve: "peak 0.99", "zero"
Rename: "res_l"

selectObject: "Sound XXXX_mono"
plusObject: "Sound imp_r"
Convolve: "peak 0.99", "zero"
Rename: "res_r"

# --- Combine to stereo result ---
selectObject: "Sound res_l"
plusObject: "Sound res_r"
Combine to stereo
Rename: originalName$ + "_ping_pong"
Scale peak: 0.99

if play_after_processing
    Play
endif

# --- Cleanup (keep original + result) ---
# Remove ONLY intermediates created by this script.
selectObject: "Sound XXXX_src"
plusObject: "Sound XXXX_resampled"
plusObject: "Sound XXXX_mono"
plusObject: "PointProcess pp_l"
plusObject: "PointProcess pp_r"
plusObject: "Sound imp_l"
plusObject: "Sound imp_r"
plusObject: "Sound res_l"
plusObject: "Sound res_r"
Remove

# Reselect final result (original remains in Objects)
selectObject: "Sound " + originalName$ + "_ping_pong"


