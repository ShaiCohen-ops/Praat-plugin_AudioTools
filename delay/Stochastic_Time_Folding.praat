form Adaptive Time-Folding Processing
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
