# Vibrato (sine LFO) — defaults baked in
# Assumes a Sound is selected.

delay_ms = 5.0
depth = 0.10
rate_hz = 5.0
phase_rad = 0.0

Copy... original
selectObject: "Sound original"
sampling = Get sampling frequency
base = round(delay_ms * sampling / 1000)

Formula... self [max(1, min(ncol, col + round('base' * (1 + 'depth' * sin(2*pi*'rate_hz'*x + 'phase_rad')))))]

Rename... vibrato_sine
Play


