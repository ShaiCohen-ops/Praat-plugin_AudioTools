# VARIATION 5: "Temporal Warping" - Non-linear time distortion
Copy... soundObj
warp_stages = 6
a = Get number of samples
for stage from 1 to warp_stages
    warp_factor = stage / warp_stages
    max_displacement = a * 0.1 * warp_factor
    time_curve = sin(pi * stage / warp_stages)
    displacement = max_displacement * randomUniform(0.3, 1.0) * time_curve
    Formula: "self * (1 - 'warp_factor' * 0.1) + 'warp_factor' * 0.3 * (self[col+'displacement'] - self[col])"
endfor
Scale peak: 0.99
Play