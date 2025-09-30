# Spectral swirl effect: sinusoidally shift frequency bins

# Select the input sound
sound$ = selected$("Sound")
select Sound 'sound$'

# Convert to complex spectrum
origSpec = To Spectrum: "no"
Rename: "origSpec"

# Make a copy to modify
swirlSpec = Copy: "swirlSpec"

# Number of sinusoidal cycles
cycles = 4

# Maximum bin shift
depth = 100

# Apply the swirl: compute a shifted index with sin modulation,
# then clamp it to [1, ncol] and pick the corresponding bin
Formula: "if row = 1 then if round(col + 'depth' * sin(2 * pi * 'cycles' * col / ncol)) < 1 then Spectrum_origSpec[1,1] else if round(col + 'depth' * sin(2 * pi * 'cycles' * col / ncol)) > ncol then Spectrum_origSpec[1,ncol] else Spectrum_origSpec[1, round(col + 'depth' * sin(2 * pi * 'cycles' * col / ncol))] fi fi else if round(col + 'depth' * sin(2 * pi * 'cycles' * col / ncol)) < 1 then Spectrum_origSpec[2,1] else if round(col + 'depth' * sin(2 * pi * 'cycles' * col / ncol)) > ncol then Spectrum_origSpec[2,ncol] else Spectrum_origSpec[2, round(col + 'depth' * sin(2 * pi * 'cycles' * col / ncol))] fi fi fi"

# Convert back to a sound
swirled_sound = To Sound
Rename: "'sound$'_spectral_swirl"

# Normalise to avoid clipping
Scale peak: 0.99

# Clean up the intermediate spectra
selectObject: origSpec, swirlSpec
Remove

# Select and report on the result
selectObject: swirled_sound
writeInfoLine: "Spectral swirl processing complete!"
appendInfoLine: "Original: ", sound$
appendInfoLine: "Created: ", sound$, "_spectral_swirl"
appendInfoLine: "Cycles: ", string$(cycles)
appendInfoLine: "Depth: ", string$(depth)
