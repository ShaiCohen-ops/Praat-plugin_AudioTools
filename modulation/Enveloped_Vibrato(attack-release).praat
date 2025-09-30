# Enveloped Vibrato (attack/release) — defaults baked in
# Assumes a Sound is selected.

delay_ms = 6.0
depth = 0.15
rate_hz = 5.5
attack_s = 0.25
release_s = 0.35

Copy... soundObj
selectObject: "Sound soundObj"
sampling = Get sampling frequency
dur = Get total duration
base = round(delay_ms * sampling / 1000)

Formula... self [max(1, min(ncol, col + round('base' + 'base'*'depth'*max(0, min(1, min(x/'attack_s', ('dur' - x)/'release_s')))*sin(2*pi*'rate_hz'*x))))]

Scale peak... 0.99
Rename... vibrato_enveloped
Play

