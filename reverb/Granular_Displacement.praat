# VARIATION 4: "Granular Displacement" - Variable grain-based processing
Copy... soundObj
grains = 8
a = Get number of samples
grain_size = a / grains
for grain from 1 to grains
    grain_delay = randomUniform(10, grain_size/4)
    grain_amplitude = randomUniform(0.2, 0.8)
    start_sample = (grain - 1) * grain_size + 1
    end_sample = grain * grain_size
    Formula (part): start_sample, end_sample, 1, 1, "self + 'grain_amplitude' * (self[col+'grain_delay'] - self[col])"
endfor
Scale peak: 0.99
Play