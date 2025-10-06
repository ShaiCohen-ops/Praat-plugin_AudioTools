# ============================================================
# Praat AudioTools - Harmonic Resonance Boost.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral analysis or frequency-domain processing script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Harmonic Resonance Boost
    comment This script boosts harmonic frequencies and attenuates others
    comment WARNING: This process can have long runtime on long files
    comment due to FFT calculations
    comment Spectrum parameters:
    boolean fast_fourier yes
    comment Harmonic boost parameters:
    positive fundamental_frequency 440
    comment (base frequency for harmonic series in Hz)
    positive harmonic_bandwidth 50
    comment (width of harmonic region in Hz)
    positive harmonic_boost 1.5
    comment (multiplier for harmonic frequencies)
    comment Frequency range attenuations:
    positive mid_freq_cutoff 6000
    comment (transition point between mid and high frequency)
    positive low_mid_attenuation 0.6
    comment (attenuation below mid_freq_cutoff)
    positive high_freq_attenuation 0.4
    comment (attenuation above mid_freq_cutoff)
    comment Output options:
    positive scale_peak 0.88
    boolean play_after_processing 1
    boolean keep_intermediate_objects 0
endform

# Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# Get the original sound name
originalName$ = selected$("Sound")

# Get sampling frequency
sampling_rate = Get sampling frequency

# Convert to spectrum
spectrum = To Spectrum: fast_fourier

# Apply harmonic resonance boost with frequency-dependent attenuation
Formula: "if col mod 'fundamental_frequency' < 'harmonic_bandwidth' then self[1,col] * 'harmonic_boost' else if col < 'mid_freq_cutoff' then self[1,col] * 'low_mid_attenuation' else self[1,col] * 'high_freq_attenuation' fi fi"

# Convert back to sound
result = To Sound

# Rename result
Rename: originalName$ + "_harmonic_boost"

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif

# Clean up intermediate objects unless requested to keep
if not keep_intermediate_objects
    select spectrum
    Remove
endif