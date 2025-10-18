# ============================================================
# Praat AudioTools - Spectral_Echo_Cascade.praat
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

form Fibonacci Cascade Delay Processing
    optionmenu Preset: 1
        option "Default (balanced)"
        option "Gentle Echoes"
        option "Dense Cluster"
        option "Long Tails"
        option "Custom"
    comment Cascade parameters:
    natural cascade_levels 6
    positive decay_rate 0.75
    comment Delay shift parameters:
    positive delay_base 5
    comment Spectral coloring modulation:
    positive coloring_center 0.5
    positive coloring_depth 0.5
    comment Output options:
    positive scale_peak 0.88
    boolean play_after_processing 1
endform

# Apply preset values if not Custom
if preset = 1
    # Default (balanced)
    cascade_levels = 6
    decay_rate = 0.75
    delay_base = 5
    coloring_center = 0.5
    coloring_depth = 0.5
    scale_peak = 0.88
elsif preset = 2
    # Gentle Echoes
    cascade_levels = 4
    decay_rate = 0.85
    delay_base = 7
    coloring_center = 0.45
    coloring_depth = 0.35
    scale_peak = 0.88
elsif preset = 3
    # Dense Cluster
    cascade_levels = 8
    decay_rate = 0.7
    delay_base = 4
    coloring_center = 0.55
    coloring_depth = 0.65
    scale_peak = 0.88
elsif preset = 4
    # Long Tails
    cascade_levels = 7
    decay_rate = 0.9
    delay_base = 9
    coloring_center = 0.5
    coloring_depth = 0.4
    scale_peak = 0.88
endif

# Copy the sound object
Copy... soundObj

# Get the number of samples
a = Get number of samples

# Main cascade processing loop
for level from 1 to cascade_levels
    # Fibonacci-based delay progression
    if level = 1
        fibPrev = 1
        fibCurrent = 1
    else
        fibNext = fibPrev + fibCurrent
        fibPrev = fibCurrent
        fibCurrent = fibNext
    endif
    
    delayShift = a / (delay_base + fibCurrent)
    currentDecay = decay_rate ^ level
    
    # Multi-tap delay with spectral coloring
    Formula: "self + self [col - round(delayShift)] * currentDecay * ('coloring_center' + 'coloring_depth' * cos(level * 2 * pi * col / a))"
endfor

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif
