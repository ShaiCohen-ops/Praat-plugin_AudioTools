# Dual-Tap Chorus — defaults baked in (no form)
# Assumes a Sound is selected.

delay_ms = 8.0
depth = 0.12
rate1_hz = 3.7
rate2_hz = 5.1
phase1 = 0.0
phase2 = 2.2

Copy... soundObj
selectObject: "Sound soundObj"
sampling = Get sampling frequency
base = round(delay_ms * sampling / 1000)

Formula... ( self [max(1, min(ncol, col + round('base' + 'base'*'depth'*sin(2*pi*'rate1_hz'*x + 'phase1'))))] + self [max(1, min(ncol, col + round('base' + 'base'*'depth'*sin(2*pi*'rate2_hz'*x + 'phase2'))))] ) / 2

Scale peak... 0.99
Rename... chorus_dual_tap
Play


