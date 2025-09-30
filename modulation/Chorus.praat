# Chorus / Unison (3 taps) — defaults baked in
# Assumes a Sound is selected.

delay_ms = 8.0
depth = 0.12
rate1_hz = 3.6
rate2_hz = 4.7
rate3_hz = 5.8

Copy... original
selectObject: "Sound original"
sampling = Get sampling frequency
base = round(delay_ms * sampling / 1000)

Formula... ( self [max(1, min(ncol, col + round('base' * (1 + 'depth' * sin(2*pi*'rate1_hz'*x))))) ] + self [max(1, min(ncol, col + round('base' * (1 + 'depth' * sin(2*pi*'rate2_hz'*x + 1.9))))) ] + self [max(1, min(ncol, col + round('base' * (1 + 'depth' * sin(2*pi*'rate3_hz'*x + 3.1))))) ] ) / 3

Rename... chorus_unison
Play


