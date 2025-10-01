# Formant Synthesis Script for Praat
# This script creates synthetic vowel sounds using formant frequencies

# User-defined parameters
form Formant Synthesis Parameters
    comment Basic settings:
    positive duration 0.5
    positive pitch 120
    positive sampling_frequency 44100
    
    comment Formant frequencies (Hz):
    positive f1 500
    positive f2 1500
    positive f3 2500
    positive f4 3500
    
    comment Formant bandwidths (Hz):
    positive bw1 50
    positive bw2 70
    positive bw3 110
    positive bw4 150
    
    comment Voice quality:
    positive voicing_amplitude 60
    boolean enable_vibrato 1
    positive vibrato_rate 6
    positive vibrato_depth 10
    
    comment Output:
    word output_name synthesized_vowel
    boolean play_sound 1
    boolean save_to_file 0
endform

# Step 1: Create KlattGrid
klattGrid = Create KlattGrid: "synth", 0, duration, 6, 1, 1, 6, 1, 1, 1

# Step 2: Set pitch contour
selectObject: klattGrid
if enable_vibrato
    # Add simple vibrato
    Add pitch point: 0, pitch
    Add pitch point: duration/4, pitch + vibrato_depth
    Add pitch point: duration/2, pitch
    Add pitch point: 3*duration/4, pitch - vibrato_depth
    Add pitch point: duration, pitch
else
    Add pitch point: duration/2, pitch
endif

# Step 3: Set oral formant frequencies
selectObject: klattGrid
for i from 1 to 4
    f_val = f'i'
    Add oral formant frequency point: i, duration/2, f_val
endfor

# Step 4: Set oral formant bandwidths
selectObject: klattGrid
for i from 1 to 4
    bw_val = bw'i'
    Add oral formant bandwidth point: i, duration/2, bw_val
endfor

# Step 5: Set voicing amplitude
selectObject: klattGrid
Add voicing amplitude point: duration/2, voicing_amplitude

# Step 6: Synthesize sound
selectObject: klattGrid
To Sound
synthesized = selected("Sound")

# Step 7: Set sampling frequency
selectObject: synthesized
sampled_sound = Resample: sampling_frequency, 50

# Clean up and present result
selectObject: sampled_sound
Rename: output_name$
Scale peak: 0.99

# Play the synthesized sound if requested
if play_sound
    Play
endif

# Save to file if requested
if save_to_file
    selectObject: sampled_sound
    Save as WAV file: output_name$ + ".wav"
endif

# Select final output for inspection
selectObject: sampled_sound

# Print information
writeInfoLine: "Formant synthesis complete!"
appendInfoLine: "Duration: ", duration, " seconds"
appendInfoLine: "Pitch: ", pitch, " Hz"
appendInfoLine: "Formants (Hz): F1=", f1, " F2=", f2, " F3=", f3, " F4=", f4
appendInfoLine: "Vibrato: ", if enable_vibrato then "Yes" else "No" fi