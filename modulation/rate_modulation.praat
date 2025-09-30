# Vibrato (rate modulation) — defaults baked in
# Assumes a Sound is selected.

delay_ms = 5.0
depth = 0.10
base_rate_hz = 4.0
rate_sensitivity = 3.0

Copy... soundObj
selectObject: "Sound soundObj"
sampling = Get sampling frequency
base = round(delay_ms * sampling / 1000)

Formula... self [max(1, min(ncol, col + round('base' * (1 + 'depth' * sin(2*pi*x*('base_rate_hz' + 'rate_sensitivity'*(0.5 + 0.5*sin(2*pi*0.8*x))))))))]

Rename... vibrato_rate_mod
Play



