# ============================================================
# Praat AudioTools - crunchy_2.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Non-linear distortion or waveshaping script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Harsh Distortion Effect
    optionmenu Preset: 1
        option "Default (balanced)"
        option "Light Drive"
        option "Heavy Industrial"
        option "Stutter Gate"
        option "Custom"
    comment This script applies extreme distortion with gating
    comment Distortion parameters:
    positive base_amplitude 0.5
    positive modulation_amplitude 0.3
    positive modulation_frequency 100
    comment Gating parameters:
    positive gate_period 0.05
    positive gate_duty_cycle 0.025
    comment Output options:
    positive scale_peak 0.99
    boolean play_after_processing 1
endform

# Apply preset values if not Custom
if preset = 1
    # Default (balanced)
    base_amplitude = 0.5
    modulation_amplitude = 0.3
    modulation_frequency = 100
    gate_period = 0.05
    gate_duty_cycle = 0.025
    scale_peak = 0.99
    play_after_processing = 1
elsif preset = 2
    # Light Drive
    base_amplitude = 0.4
    modulation_amplitude = 0.2
    modulation_frequency = 80
    gate_period = 0.07
    gate_duty_cycle = 0.035
    scale_peak = 0.99
    play_after_processing = 1
elsif preset = 3
    # Heavy Industrial
    base_amplitude = 0.7
    modulation_amplitude = 0.4
    modulation_frequency = 150
    gate_period = 0.03
    gate_duty_cycle = 0.015
    scale_peak = 0.99
    play_after_processing = 1
elsif preset = 4
    # Stutter Gate
    base_amplitude = 0.6
    modulation_amplitude = 0.25
    modulation_frequency = 90
    gate_period = 0.02
    gate_duty_cycle = 0.01
    scale_peak = 0.99
    play_after_processing = 1
endif

# Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# Get the name of the original sound
originalName$ = selected$("Sound")

# Copy the sound object
Copy: originalName$ + "_distorted"

# Apply harsh distortion with modulation and gating
Formula: "if self > 0 then 1 else -1 fi * ('base_amplitude' + 'modulation_amplitude' * sin('modulation_frequency' * x)) * if (x mod 'gate_period' > 'gate_duty_cycle') then 1 else 0 fi"

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif
