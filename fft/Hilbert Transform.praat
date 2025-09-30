# Hilbert Transform - Extract and Apply Envelope Backwards in Time
# Select a Sound object before running this script

# Get the selected sound name
sound$ = selected$("Sound")
select Sound 'sound$'
original_duration = Get total duration

# Extract envelope using Hilbert transform
spectrum = To Spectrum: "no"
Rename: "original_spectrum"

# Create Hilbert transform
hilbert_spectrum = Copy: "hilbert_spectrum"
Formula: "if row=1 then Spectrum_original_spectrum[2,col] else -Spectrum_original_spectrum[1,col] fi"

# Convert back to time domain
hilbert_sound = To Sound
Rename: "hilbert_sound"

# Calculate envelope from analytic signal
select Sound 'sound$'
env_sound = Copy: "envelope_temp"
Formula: "sqrt(self^2 + Sound_hilbert_sound[]^2)"
Rename: "'sound$'_envelope"

# Scale the envelope
Scale peak: 0.99

# Optional: Make envelope faster or less smoothed
# Formula: "self^0.8"

# High-pass filter to reduce low-frequency dominance
Filter (pass Hann band): 50, 0, 10

# Create time-reversed version of original sound
select Sound 'sound$'
reverse_sound = Copy: "'sound$'_reversed"
Formula: "self[(ncol-col+1)]"

# Apply envelope backwards in time
select reverse_sound
reversed_with_env = Copy: "'sound$'_reversed_with_env"
Formula: "self * Sound_'sound$'_envelope[col]"

# Reverse back to normal time
select reversed_with_env
final_sound = Copy: "'sound$'_time_reverse_env"
Formula: "self[(ncol-col+1)]"
Rename: "'sound$'_time_reverse_env"

# Scale final output to prevent clipping
Scale peak: 0.99

# Cleanup intermediate objects
selectObject: spectrum, hilbert_spectrum, hilbert_sound
plusObject: reverse_sound
plusObject: reversed_with_env
plusObject: env_sound
Remove

# Select the final result
selectObject: final_sound

writeInfoLine: "Time-reverse envelope processing complete!"
appendInfoLine: "Original: ", sound$
appendInfoLine: "Created: ", sound$, "_time_reverse_env"
appendInfoLine: "Duration: ", fixed$(original_duration, 3), " seconds"
appendInfoLine: "Envelope applied backwards in time"