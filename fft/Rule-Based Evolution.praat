# ============================================================
# Praat AudioTools - Rule-Based Evolution.praat
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

form Spectral Cellular Automata
    comment This script applies rule-based evolution pattern to spectrum
    comment WARNING: This process can have long runtime on long files
    comment due to FFT calculations
    comment Spectrum parameters:
    boolean fast_fourier yes
    comment Cellular automata rule parameters:
    positive rule_divisor_1 100
    positive rule_divisor_2 150
    comment (controls the pattern period of the two rules)
    comment Active cells (XOR pattern) parameters:
    positive active_multiplier 1.5
    positive modulation_divisor 500
    comment (sine modulation for active cells)
    comment Inactive cells attenuation:
    positive inactive_multiplier 0.2
    comment Output options:
    positive scale_peak 0.84
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

# Apply cellular automata rule (XOR-like pattern)
# Active when: (rule1 even AND rule2 odd) OR (rule1 odd AND rule2 even)
Formula: "if (round(col/'rule_divisor_1') mod 2 = 0 and round(col/'rule_divisor_2') mod 2 = 1) or (round(col/'rule_divisor_1') mod 2 = 1 and round(col/'rule_divisor_2') mod 2 = 0) then self[1,col] * 'active_multiplier' * sin(col/'modulation_divisor') else self[1,col] * 'inactive_multiplier' fi"

# Convert back to sound
result = To Sound

# Rename result
Rename: originalName$ + "_cellular_automata"

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