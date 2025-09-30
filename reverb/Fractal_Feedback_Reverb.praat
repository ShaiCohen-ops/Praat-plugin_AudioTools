# VARIATION 2: Fractal Feedback Reverb
# Self-referential delays that create complex interference patterns

Copy... "reverb_copy"

iterations = 32
seed_delay = 0.08
chaos_factor = 1.8
memory_depth = 4

for i from 1 to iterations
    primary_delay = seed_delay * (chaos_factor ^ (i mod memory_depth))
    secondary_delay = primary_delay / chaos_factor
    
    amp1 = 0.18 * (1 - i/iterations) * randomUniform (0.6, 1.4)
    amp2 = amp1 * 0.75
    
    # Primary reflection
    Formula... self + amp1 * self (x - primary_delay)
    # Secondary bounce
    Formula... self + amp2 * self (x - secondary_delay) * cos (2*pi*x*30)
endfor
Play