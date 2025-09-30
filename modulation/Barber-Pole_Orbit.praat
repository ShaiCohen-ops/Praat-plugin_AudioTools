# Barber-Pole Orbit (no form; defaults baked in)
# Assumes a Sound is selected.

turns = 5
delay_ms = 7.0
depth = 0.10
base_rate_hz = 3.8
drift_hz = 0.12
phase_offset = 1.2

# Work on a copy so the original stays untouched
Copy... soundObj
sampling = Get sampling frequency
base = round(delay_ms * sampling / 1000)

for t from 1 to 'turns'
    w = 1 / (t + 1)
    ; upward-drifting halo
    Formula... self + self [max(1, min(ncol, col + round('base' + 'base'*'depth'*sin(2*pi*'base_rate_hz'*x + 2*pi*'drift_hz'*x + 't'*0.3))))] * 'w'
    ; downward-drifting halo
    Formula... self + self [max(1, min(ncol, col + round('base' + 'base'*'depth'*sin(2*pi*'base_rate_hz'*x - 2*pi*'drift_hz'*x + 'phase_offset' - 't'*0.3))))] * 'w'
endfor

Scale peak... 0.95
Rename... barber_pole_orbit
Play

