# ============================================================
# Praat AudioTools - Mirror at Harmonic Intervals.praat
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

form Harmonic Mirror - Mirror at Harmonic Intervals
    comment This script mirrors frequencies at harmonic intervals
    comment WARNING: This process can have long runtime on long files
    comment due to FFT calculations
    comment Spectrum parameters:
    boolean fast_fourier yes
    comment Harmonic mirror parameters:
    positive fundamental_frequency 220
    comment (base frequency for harmonic intervals in Hz)
    positive harmonic_bandwidth 50
    comment (width of harmonic region to mirror in Hz)
    positive mirror_multiplier 1.2
    comment (boost for mirrored content)
    comment Non-harmonic attenuation:
    positive non_harmonic_multiplier 0.6
    comment (attenuation for frequencies outside harmonic regions)
    comment Output options:
    positive scale_peak 0.89
    boolean play_after_processing 1
    boolean keep_intermediate_objects 0
endform

# Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# Get the original sound name
originalName$ = selected$("Sound")

# Get sampling frequency and calculate Nyquist
sampling_rate = Get sampling frequency
nyquist = sampling_rate / 2

# Convert to spectrum
spectrum = To Spectrum: fast_fourier

# Apply harmonic mirroring
# At harmonic intervals: add mirrored high-frequency content
# Outside harmonics: attenuate
Formula: "if col mod 'fundamental_frequency' < 'harmonic_bandwidth' and col < nyquist/2 then self[1,col] + self[1,nyquist-col] * 'mirror_multiplier' else self[1,col] * 'non_harmonic_multiplier' fi"

# Convert back to sound
result = To Sound

# Rename result
Rename: originalName$ + "_harmonic_mirror"

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