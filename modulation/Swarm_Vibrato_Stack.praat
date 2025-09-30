# Swarm Vibrato Stack — defaults baked in
# Assumes a Sound is selected.

layers = 6
delay_ms = 6.0
depth = 0.12
base_rate_hz = 3.0
phase_step = 0.9

Copy... soundObj
selectObject: "Sound soundObj"
sampling = Get sampling frequency
base = round(delay_ms * sampling / 1000)

for d from 1 to 'layers'
    rate = 'base_rate_hz' * d
    phase = 'phase_step' * d
    weight = 1 / (d + 1)
    Formula... self + self [max(1, min(ncol, col + round('base' * (1 + 'depth' * sin(2*pi*rate*x + phase))))) ] * weight
endfor

Scale peak... 0.95
Rename... vibrato_swarm_stack
Play

