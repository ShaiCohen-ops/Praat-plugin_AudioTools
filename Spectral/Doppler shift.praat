# ============================================================
# Praat AudioTools - Doppler shift.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral analysis or frequency-domain processing script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Doppler Shift Effect
    comment This script simulates accelerating frequency change (Doppler effect)
    comment Presets:
    optionmenu preset: 1
        option Default
        option Strong Doppler
        option Subtle Doppler
        option Fast Acceleration
        option Heavy Decay
    comment Doppler shift parameters:
    positive base_shift 1.0
    positive shift_amount 0.5
    positive acceleration_exponent 2
    comment (higher = more dramatic acceleration)
    comment Decay parameters:
    positive decay_base 15
    comment (simulates distance/amplitude loss)
    comment Output options:
    positive scale_peak 0.99
    boolean play_after_processing 1
endform

# Apply preset values
if preset = 2 ; Strong Doppler
    shift_amount = 1.0
elif preset = 3 ; Subtle Doppler
    shift_amount = 0.2
elif preset = 4 ; Fast Acceleration
    acceleration_exponent = 4
elif preset = 5 ; Heavy Decay
    decay_base = 25
endif

# Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# Copy the sound object
Copy: "soundObj"

# Get name and ID
name$ = selected$("Sound")
sound = selected("Sound")

# Apply Doppler shift with accelerating frequency change
Formula: "self[col/('base_shift' + 'shift_amount' * ((x-xmin)/(xmax-xmin))^'acceleration_exponent')] - self[col*('base_shift' + 'shift_amount' * ((x-xmin)/(xmax-xmin))^'acceleration_exponent')]"

# Apply exponential decay (distance effect)
Formula: "self * 'decay_base'^(-(x-xmin)/(xmax-xmin))"

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif