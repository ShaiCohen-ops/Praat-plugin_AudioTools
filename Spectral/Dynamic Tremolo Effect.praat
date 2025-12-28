# ============================================================
# Praat AudioTools - Dynamic Tremolo Effect.praat
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

form Dynamic Tremolo Effect
    comment This script applies frequency-dependent tremolo modulation
    comment WARNING: This process can have long runtime on long files
    comment due to FFT calculations
    comment Presets:
    optionmenu preset: 1
        option Default
        option Deep Tremolo
        option Subtle Tremolo
        option Fast Tremolo
        option Strong High-Freq Attenuation
    comment Spectrum parameters:
    boolean fast_fourier yes
    comment Tremolo modulation parameters:
    positive low_freq_cutoff 8000
    comment (frequencies below this get tremolo modulation)
    positive tremolo_minimum 0.3
    positive tremolo_maximum 0.7
    comment (tremolo ranges from minimum to minimum+maximum)
    positive tremolo_frequency_divisor 500
    comment (higher = slower tremolo across spectrum)
    comment High frequency attenuation:
    positive high_freq_attenuation 0.8
    comment (applied to frequencies above cutoff)
    comment Output options:
    positive scale_peak 0.9
    boolean play_after_processing 1
    boolean keep_intermediate_objects 0
endform

# Apply preset values
if preset = 2 ; Deep Tremolo
    tremolo_minimum = 0.2
    tremolo_maximum = 0.9
elif preset = 3 ; Subtle Tremolo
    tremolo_minimum = 0.4
    tremolo_maximum = 0.4
elif preset = 4 ; Fast Tremolo
    tremolo_frequency_divisor = 200
elif preset = 5 ; Strong High-Freq Attenuation
    high_freq_attenuation = 0.5
endif

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

# Apply dynamic tremolo effect
Formula: "if col < 'low_freq_cutoff' then self[1,col] * ('tremolo_minimum' + 'tremolo_maximum' * cos(col/'tremolo_frequency_divisor')^2) else self[1,col] * 'high_freq_attenuation' fi"

# Convert back to sound
result = To Sound

# Rename result
Rename: originalName$ + "_tremolo"

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif

# Clean up intermediate objects unless requested to keep
if not keep_intermediate_objects
    selectObject: spectrum
    Remove
endif