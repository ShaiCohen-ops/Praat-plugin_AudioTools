# ============================================================
# Praat AudioTools - Magnetic_Tape_Degradation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Delay or temporal structure script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Tape Degradation Simulation
    optionmenu Preset: 1
        option "Default (balanced)"
        option "Mild Wear"
        option "Vintage Heavy"
        option "Flutter / Wow"
        option "Custom"
    comment Tape generation parameters:
    natural generations 6
    comment Tape hysteresis effect:
    positive hysteresis_current 0.7
    positive hysteresis_previous 0.3
    comment Print-through effect:
    positive print_through_initial 0.25
    positive print_through_decay 0.8
    natural print_offset_divisor 100
    comment Bias modulation range (for randomization):
    positive bias_min 0.8
    positive bias_max 1.2
    comment Or use a fixed bias:
    boolean use_fixed_bias 0
    positive fixed_bias 1.0
    comment High-frequency loss parameters:
    positive hf_loss_rate 0.1
    positive hf_smoothing 0.9
    comment Bias modulation depth:
    positive bias_mod_center 0.9
    positive bias_mod_depth 0.1
    comment Output options:
    positive scale_peak 0.87
    boolean play_after_processing 1
endform

# Apply preset values if not Custom
if preset = 1
    # Default (balanced)
    generations = 6
    hysteresis_current = 0.7
    hysteresis_previous = 0.3
    print_through_initial = 0.25
    print_through_decay = 0.8
    print_offset_divisor = 100
    bias_min = 0.8
    bias_max = 1.2
    fixed_bias = 1.0
    hf_loss_rate = 0.1
    hf_smoothing = 0.9
    bias_mod_center = 0.9
    bias_mod_depth = 0.1
    scale_peak = 0.87
elsif preset = 2
    # Mild Wear
    generations = 3
    hysteresis_current = 0.6
    hysteresis_previous = 0.4
    print_through_initial = 0.10
    print_through_decay = 0.85
    print_offset_divisor = 120
    bias_min = 0.95
    bias_max = 1.05
    fixed_bias = 1.0
    hf_loss_rate = 0.05
    hf_smoothing = 0.95
    bias_mod_center = 0.95
    bias_mod_depth = 0.05
    scale_peak = 0.87
elsif preset = 3
    # Vintage Heavy
    generations = 10
    hysteresis_current = 0.8
    hysteresis_previous = 0.2
    print_through_initial = 0.35
    print_through_decay = 0.75
    print_offset_divisor = 80
    bias_min = 0.7
    bias_max = 1.3
    fixed_bias = 1.0
    hf_loss_rate = 0.18
    hf_smoothing = 0.85
    bias_mod_center = 0.85
    bias_mod_depth = 0.15
    scale_peak = 0.87
elsif preset = 4
    # Flutter / Wow
    generations = 6
    hysteresis_current = 0.7
    hysteresis_previous = 0.3
    print_through_initial = 0.20
    print_through_decay = 0.8
    print_offset_divisor = 90
    bias_min = 0.6
    bias_max = 1.4
    fixed_bias = 1.0
    hf_loss_rate = 0.10
    hf_smoothing = 0.90
    bias_mod_center = 0.90
    bias_mod_depth = 0.20
    scale_peak = 0.87
endif

# Copy the sound object
Copy... soundObj

# Get the number of samples
a = Get number of samples

# Initialize print-through
printThrough = print_through_initial

# Determine bias
if use_fixed_bias
    bias = fixed_bias
else
    bias = randomUniform(bias_min, bias_max)
endif

# Main tape degradation loop
for gen from 1 to generations
    # Tape hysteresis effect
    Formula: "'hysteresis_current' * self + 'hysteresis_previous' * self[col-1]"
    
    # Print-through effect (bleeding between layers)
    printOffset = round(a / print_offset_divisor)
    Formula: "self + printThrough * (self[col - printOffset] + self[col + printOffset])/2"
    
    # High-frequency loss per generation
    Formula: "self * (1 - 'hf_loss_rate' * gen) + 'hf_smoothing' * (self[col-1] + self[col+1])/2"
    
    # Bias modulation
    Formula: "self * ('bias_mod_center' + 'bias_mod_depth' * sin(2 * pi * bias * col / a))"
    
    # Decay print-through for next generation
    printThrough = printThrough * print_through_decay
endfor

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif
