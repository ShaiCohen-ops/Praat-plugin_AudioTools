# Golden-Chaos Vibrato — defaults baked in
# Assumes a Sound is selected.

delay_ms = 6.0
depth = 0.14
r1_hz = 3.14159
r2_hz = 2.71828
r3_hz = 1.61803
mix2 = 0.6
mix3 = 0.4

Copy... soundObj
selectObject: "Sound soundObj"
sampling = Get sampling frequency
base = round(delay_ms * sampling / 1000)

Formula... self [max(1, min(ncol, col + round('base' + 'base'*'depth'*sin(2*pi*'r1_hz'*x + 'mix2'*sin(2*pi*'r2_hz'*x) + 'mix3'*sin(2*pi*'r3_hz'*x)))))]

Scale peak... 0.99
Rename... vibrato_golden_chaos
Play

