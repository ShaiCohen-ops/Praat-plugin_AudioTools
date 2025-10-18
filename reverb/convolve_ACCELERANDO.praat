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

form Accelerando Convolution
    optionmenu Preset: 1
        option "Default (balanced)"
        option "Fast Accel (quick ramp)"
        option "Slow Accel (gentle)"
        option "Sparse Hits"
        option "Dense Finale"
        option "Custom"
    comment This script creates accelerating impulse train convolution
    positive duration_seconds 2.0
    positive first_hit_time 0.10
    natural number_of_pulses 24
    positive gap_shrink_ratio 0.85
    comment (0 < ratio < 1, lower = faster acceleration)
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
    ; Default (balanced) -> keep form defaults
elsif preset = 2
    # Fast Accel (quick ramp)
    first_hit_time = 0.08
    number_of_pulses = 28
    gap_shrink_ratio = 0.7
    pulse_width = 0.018
elsif preset = 3
    # Slow Accel (gentle)
    first_hit_time = 0.12
    number_of_pulses = 20
    gap_shrink_ratio = 0.92
    pulse_width = 0.024
elsif preset = 4
    # Sparse Hits
    first_hit_time = 0.15
    number_of_pulses = 12
    gap_shrink_ratio = 0.8
    pulse_width = 0.02
elsif preset = 5
    # Dense Finale
    first_hit_time = 0.06
    number_of_pulses = 36
    gap_shrink_ratio = 0.78
    pulse_width = 0.018
endif

# --- Safety: need a selected Sound ---
if numberOfSelected("Sound") < 1
    exitScript: "Select a Sound in the Objects window first."
endif

# --- Prep source (keep original untouched) ---
selectObject: selected("Sound", 1)
originalName$ = selected$("Sound")

# Working copies with explicit names to avoid *_44100 leftovers
Copy: "XXXX_src"
selectObject: "Sound XXXX_src"
Resample: sampling_frequency, 50
Rename: "XXXX_resampled"

# --- Parameter sanity checks ---
if (gap_shrink_ratio <= 0) or (gap_shrink_ratio >= 1)
    exitScript: "gap_shrink_ratio must be between 0 and 1 (exclusive)."
endif

# Calculate initial gap
remain = duration_seconds - first_hit_time
if remain <= 0
    exitScript: "Duration must be greater than first hit time."
endif

den = 1 - gap_shrink_ratio^number_of_pulses
if den = 0
    exitScript: "Choose ratio so that 1 - ratio^npulse ≠ 0."
endif

g0 = remain * (1 - gap_shrink_ratio) / den

# --- Create accelerating point process ---
Create empty PointProcess: "pp_accel", 0, duration_seconds
selectObject: "PointProcess pp_accel"
t = first_hit_time
i = 1
while i <= number_of_pulses and t < duration_seconds
    Add point: t
    gap = g0 * gap_shrink_ratio^(i - 1)
    t = t + gap
    i = i + 1
endwhile

# --- Convert to pulse train ---
To Sound (pulse train): sampling_frequency, pulse_amplitude, pulse_width, pulse_period
Rename: "impulse_accel"
Scale peak: 0.99

# --- Convolve ---
selectObject: "Sound XXXX_resampled"
plusObject: "Sound impulse_accel"
Convolve: "peak 0.99", "zero"
Rename: originalName$ + "_accelerando"

if play_after_processing
    Play
endif

# --- Cleanup (keep original + result) ---
selectObject: "Sound XXXX_src"
plusObject: "Sound XXXX_resampled"
plusObject: "PointProcess pp_accel"
plusObject: "Sound impulse_accel"
Remove

# Reselect final result (original remains)
selectObject: "Sound " + originalName$ + "_accelerando"
