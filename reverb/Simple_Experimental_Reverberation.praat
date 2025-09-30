# Simple Experimental Reverberation
# A minimalist approach with creative variations

n = 40
amplitude = 0.15

# Get selected sound
sound = selected()
select sound
dur = Get total duration

# Create initial processed sound
Copy: "processed"

# Main processing loop
for k from 1 to n
    # Varied delay times with some randomness
    delay = 0.1 + 0.4 * (k/n) + randomUniform(-0.05, 0.05)
    
    # Modulated amplitude
    current_amp = amplitude * (0.8 + 0.2 * sin(k * 0.5))
    
    # Apply the effect with some variations
    if k mod 3 == 0
        # Reverse delay every 3rd iteration
        Formula: "self + current_amp * self(dur - x - delay)"
    elsif k mod 5 == 0
        # Pitch-shifted delay every 5th iteration
        Formula: "self + current_amp * self(x - delay) * (1 + 0.1 * sin(x * 100))"
    else
        # Standard delay with slight modulation
        Formula: "self + current_amp * self(x - delay) * (0.9 + 0.1 * randomUniform(0,1))"
    endif
    
    # Occasionally add some noise
    if randomUniform(0,1) < 0.2
        Formula: "self + (current_amp * 0.1) * randomGauss(0,1)"
    endif
endfor

# Final gentle filtering
Formula: "self * exp(-x * 0.5)"

# Rename the result
Rename: "experimental_reverb"
Play