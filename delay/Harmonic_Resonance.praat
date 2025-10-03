form Harmonic Sound Processing
    comment Harmonic processing parameters:
    natural num_iterations 7
    comment Harmonic base range (for randomization):
    positive harmonic_base_min 1.5
    positive harmonic_base_max 4.0
    comment Or use a fixed harmonic base:
    boolean use_fixed_base 0
    positive fixed_harmonic_base 2.5
    comment Amplitude decay parameters:
    positive decay_factor 0.6
    comment Output options:
    positive scale_peak 0.95
    boolean play_after_processing 1
endform

# Copy the sound object
Copy... soundObj

# Get the number of samples
a = Get number of samples

# Determine harmonic base
if use_fixed_base
    harmonicBase = fixed_harmonic_base
else
    harmonicBase = randomUniform(harmonic_base_min, harmonic_base_max)
endif

# Main harmonic processing loop
for k from 1 to num_iterations
    # Exponential harmonic progression
    shiftFactor = harmonicBase ^ k
    b = a / shiftFactor
    
    # Bidirectional formula with harmonic weighting
    Formula: "(self [col + round(b)] - self [col - round(b/2)]) * (1/k)"
    
    # Harmonic amplitude decay
    Formula: "self * (1 - k/num_iterations * 'decay_factor')"
endfor

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif
