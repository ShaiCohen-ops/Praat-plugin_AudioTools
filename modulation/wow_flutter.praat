# Vibrato (wow + flutter) — defaults baked in
# Assumes a Sound is selected.

delay_ms = 7.0
depth = 0.12
wow_rate_hz = 0.6
flutter_rate_hz = 6.5
noise_amount = 0.02

Copy... original
selectObject: "Sound original"
sampling = Get sampling frequency
base = round(delay_ms * sampling / 1000)

Formula... self [max(1, min(ncol, col + round('base' * (1 + 'depth' * (0.6*sin(2*pi*'wow_rate_hz'*x) + 0.4*sin(2*pi*'flutter_rate_hz'*x + 1.1) + 'noise_amount'*sin(2*pi*17.3*x + 0.8))))))]

Rename... vibrato_wow_flutter
Play



