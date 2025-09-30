# Chirped Vibrato (no form; defaults baked in)
# Assumes a Sound is selected.

delay_ms = 5.0
depth = 0.12
start_rate_hz = 2.0
sweep_hz_per_s = 3.0

Copy... soundObj
sampling = Get sampling frequency
base = round(delay_ms * sampling / 1000)

Formula... self [max(1, min(ncol, col + round('base' + 'base'*'depth'*sin(2*pi*x*('start_rate_hz' + 'sweep_hz_per_s'*x)))))]

Scale peak... 0.99
Rename... vibrato_chirped
Play
