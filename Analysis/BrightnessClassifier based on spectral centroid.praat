# Ultra-Fast Audio Brightness Classifier - Clean Output
# Only shows classification results

form Audio Classification
    comment Frequency bands optimized for music:
    positive low_freq 200
    positive mid_freq 1000
    positive high_freq 4000
endform

sound = selected("Sound")
if sound = 0
    exitScript: "Please select a Sound object first"
endif

sound_name$ = selected$("Sound")

# Get overall spectral analysis
select sound
To Spectrum: "yes"
spectrum = selected("Spectrum")

# Get energy in frequency bands optimized for music
select spectrum
bass = Get band energy: 100, low_freq
low_mid = Get band energy: low_freq, mid_freq  
high_mid = Get band energy: mid_freq, high_freq
high_freq_energy = Get band energy: high_freq, 10000

# Calculate spectral centroid
total_energy = bass + low_mid + high_mid + high_freq_energy

if total_energy > 0
    spectral_centroid = ((bass * 150) + (low_mid * 600) + (high_mid * 2500) + (high_freq_energy * 7500)) / total_energy
else
    spectral_centroid = 0
endif

# Classification thresholds
if spectral_centroid < 300
    category$ = "very_dark"
elsif spectral_centroid >= 300 and spectral_centroid < 600
    category$ = "dark"
elsif spectral_centroid >= 600 and spectral_centroid < 1200
    category$ = "medium"
elsif spectral_centroid >= 1200 and spectral_centroid < 2000
    category$ = "bright"
else
    category$ = "very_bright"
endif

# Clean output
appendInfoLine: sound_name$ + ": " + string$(round(spectral_centroid)) + " Hz → " + category$

# Cleanup
select spectrum
Remove