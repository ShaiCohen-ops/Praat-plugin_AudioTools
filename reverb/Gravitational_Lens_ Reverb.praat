# VARIATION 6: Gravitational Lens Reverb
# Delays bent by simulated gravitational fields

Copy... "reverb_copy"

mass_points = 12
space_curvature = 0.8
light_speed = 1.0

for mass from 1 to mass_points
    # Gravitational mass position in delay space
    mass_position = randomUniform (0.03, 0.9)
    mass_strength = randomGauss (1.2, 0.5)
    
    # Light ray bending calculation
    for ray from 1 to 8
        straight_delay = 0.05 + ray * 0.06
        
        # Calculate gravitational lensing effect
        distance_to_mass = abs (straight_delay - mass_position)
        bending = mass_strength / (distance_to_mass + 0.005)
        
        curved_delay = straight_delay + bending * space_curvature
        lensing_amplitude = 0.16 / (1 + bending)
        
        # Time dilation effect
        time_dilation = sqrt (1 - mass_strength * 0.15)
        
        Formula... self + lensing_amplitude * self (x - curved_delay * time_dilation)
    endfor
endfor
Play