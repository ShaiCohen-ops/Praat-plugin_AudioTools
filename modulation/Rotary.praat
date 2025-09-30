# Rotary (vibrato + tremolo) — defaults baked in
# Assumes a Sound is selected.

delay_ms = 6.0
depth = 0.12
vib_rate_hz = 5.0
trem_depth = 0.40
trem_rate_hz = 4.8

Copy... soundObj
selectObject: "Sound soundObj"
sampling = Get sampling frequency
base = round(delay_ms * sampling / 1000)

Formula... ( self [max(1, min(ncol, col + round('base' * (1 + 'depth' * sin(2*pi*'vib_rate_hz'*x)))))]) * (1 + 'trem_depth' * sin(2*pi*'trem_rate_hz'*x))

Rename... rotary_speaker
Scale peak... 0.99
Play

