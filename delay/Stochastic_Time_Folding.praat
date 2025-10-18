# ============================================================
# Praat AudioTools - Stochastic_Time_Folding.praat
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

form Adaptive Time-Folding Processing
    optionmenu Preset: 1
        option "Default (balanced)"
        option "Gentle Folds"
        option "Aggressive Folds"
        option "Micro Glitch"
        option "Custom"
    comment Folding parameters:
    natural fold_iterations 6
    positive initial_adaptive_threshold 0.5
    comment Adaptive threshold variation:
    positive threshold_variation_min 0.2
    positive threshold_variation_max 0.2
    positive threshold_min_limit 0.1
    positive threshold_max_limit 0.9
    comment Fold distance range:
    positive fold_distance_min 3
    positive fold_distance_max 12
    comment Amplitude variation range (for non-folded samples):
    positive amplitude_min 0.7
    positive amplitude_max 1.2
    comment Fold averaging divisor:
    positive fold_average_divisor 3
    positive fold_backward_divisor 2
    comment Output options:
    positive scale_peak 0.96
    boolean play_after_processing 1
endform

# Apply preset values if not Custom
if preset = 1
    # Default (balanced)
    fold_iterations = 6
    initial_adaptive_threshold = 0.5
    threshold_variation_min = 0.2
    threshold_variation_max = 0.2
    threshold_min_limit = 0.1
    threshold_max_limit = 0.9
    fold_distance_min = 3
    fold_distance_max = 12
    amplitude_min = 0.7
    amplitude_max = 1.2
    fold_average_divisor = 3
    fold_backward_divisor = 2
    scale_peak = 0.96
elsif preset = 2
    # Gentle Folds
    fold_iterations = 4
    initial_adaptive_threshold = 0.4
    threshold_variation_min = 0.10
    threshold_variation_max = 0.15
    threshold_min_limit = 0.15
    threshold_max_limit = 0.85
    fold_distance_min = 5
    fold_distance_max = 15
    amplitude_min = 0.9
    amplitude_max = 1.1
    fold_average_divisor = 3
    fold_backward_divisor = 2
    scale_peak = 0.96
elsif preset = 3
    # Aggressive Folds
    fold_iterations = 9
    initial_adaptive_threshold = 0.6
    threshold_variation_min = 0.25
    threshold_variation_max = 0.35
    threshold_min_limit = 0.05
    threshold_max_limit = 0.95
    fold_distance_min = 2
    fold_distance_max = 10
    amplitude_min = 0.5
    amplitude_max = 1.5
    fold_average_divisor = 2
    fold_backward_divisor = 2
    scale_peak = 0.96
elsif preset = 4
    # Micro Glitch
    fold_iterations = 12
    initial_adaptive_threshold = 0.55
    threshold_variation_min = 0.15
    threshold_variation_max = 0.25
    threshold_min_limit = 0.10
    threshold_max_limit = 0.90
    fold_distance_min = 2
    fold_distance_max = 6
    amplitude_min = 0.6
    amplitude_max = 1.4
    fold_average_divisor = 2
    fold_backward_divisor = 3
    scale_peak = 0.96
endif

# Copy the sound object
Copy... soundObj

# Get the number of samples
a = Get number of samples

# Initialize adaptive threshold
adaptiveThreshold = initial_adaptive_threshold

# Main folding processing loop
for fold from 1 to fold_iterations
    # Adaptive folding based on previous iteration
    if fold > 1
        adaptiveThreshold = adaptiveThreshold + randomUniform(threshold_variation_min, threshold_variation_max)
        adaptiveThreshold = max(threshold_min_limit, min(threshold_max_limit, adaptiveThreshold))
    endif
    
    foldDistance = a / randomUniform(fold_distance_min, fold_distance_max)
    probabilityMask = randomUniform(0, 1)
    
    # Conditional time-folding with probability gates
    Formula: "if probabilityMask < adaptiveThreshold then (self [col] + self [col + round(foldDistance)] + self [col - round(foldDistance/'fold_backward_divisor')]) / 'fold_average_divisor' else self * randomUniform('amplitude_min', 'amplitude_max') fi"
endfor

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif
