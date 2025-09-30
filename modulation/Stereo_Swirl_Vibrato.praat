# Stereo Swirl Vibrato — defaults baked in
# Assumes a stereo Sound (2 channels) is selected.

delay_ms = 6.0
depth = 0.12
rate_hz = 4.5
phase_step = 1.5707963268   ; = pi/2

Copy... soundObj
selectObject: "Sound soundObj"
sampling = Get sampling frequency
base = round(delay_ms * sampling / 1000)

Formula... self [max(1, min(ncol, col + round('base' + 'base'*'depth'*sin(2*pi*'rate_hz'*x + (row-1)*'phase_step'))))]

Scale peak... 0.99
Rename... vibrato_stereo_swirl
Play


