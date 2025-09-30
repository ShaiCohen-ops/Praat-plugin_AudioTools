# Pronounced tremolo using an absolute-sine LFO

sound$ = selected$("Sound")
select Sound 'sound$'
duration = Get total duration
samplePeriod = Get sample period
fs = 1 / samplePeriod

# Strong modulation rate (Hz); lower = slower pulses, higher = faster pulses
modRate = 7

# Create an absolute-sine modulator that swings from 0 to 1
modulator = Create Sound from formula: "'sound$'_tremoloLFO", 1, 0, duration, fs, "abs(sin(2 * pi * 'modRate' * x))"

# Apply the modulator to the original sound
select Sound 'sound$'
tremolo_sound = Copy: "'sound$'_strong_tremolo"
Formula: "self * Sound_'sound$'_tremoloLFO[col]"
Rename: "'sound$'_strong_tremolo"

# Normalise the result
Scale peak: 0.99

# Clean up the temporary modulator
selectObject: modulator
Remove

# Select and report on the result
selectObject: tremolo_sound
writeInfoLine: "Strong tremolo processing complete!"
appendInfoLine: "Original: ", sound$
appendInfoLine: "Created: ", sound$, "_strong_tremolo"
appendInfoLine: "Modulation frequency: ", string$(modRate), " Hz"
