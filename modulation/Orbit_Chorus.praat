# Orbit Chorus (dual drifting taps) — defaults baked in
# Assumes a Sound is selected.

delay_ms = 8.0
depth = 0.12
base_rate_hz = 4.2
phase_drift_hz = 0.08
phase_offset = 1.3

Copy... soundObj
selectObject: "Sound soundObj"
sampling = Get sampling frequency
base = round(delay_ms * sampling / 1000)

Formula... ( self [max(1, min(ncol, col + round('base' + 'base'*'depth'*sin(2*pi*'base_rate_hz'*x + 2*pi*'phase_drift_hz'*x))))] + self [max(1, min(ncol, col + round('base' + 'base'*'depth'*sin(2*pi*'base_rate_hz'*x + 'phase_offset' - 2*pi*'phase_drift_hz'*x))))] ) / 2

Scale peak... 0.99
Rename... chorus_orbit
Play

