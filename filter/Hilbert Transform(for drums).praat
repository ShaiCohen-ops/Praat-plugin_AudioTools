# Hilbert Transform - Extract Envelope
# Select a Sound object before running this script

# Get the selected sound name
sound$ = selected$("Sound")

# Extract envelope using Hilbert transform
select Sound 'sound$'

# 1: Convert to frequency domain
spectrum = To Spectrum: "no"
Rename: "original_spectrum"

# 2: Create Hilbert transform
hilbert_spectrum = Copy: "hilbert_spectrum" 
Formula: "if row=1 then Spectrum_original_spectrum[2,col] else -Spectrum_original_spectrum[1,col] fi"

# 3: Convert back to time domain
hilbert_sound = To Sound
Rename: "hilbert_sound"

# 4: Calculate envelope from analytic signal
select Sound 'sound$'
Copy: "envelope_temp"
Formula: "sqrt(self^2 + Sound_hilbert_sound[]^2)"
Rename: "'sound$'_ENV"

# 5: Scale the envelope
Scale peak: 0.99

# 6: Optional: Make envelope faster/less smoothed for less muffle
# Uncomment the next line if still too muffled:
# Formula: "self^0.8"

# 7: High-pass filter to reduce low-frequency dominance
Filter (pass Hann band): 50, 0, 10
Play

# Cleanup intermediate objects
select Spectrum original_spectrum
plus Spectrum hilbert_spectrum
plus Sound hilbert_sound
Remove

