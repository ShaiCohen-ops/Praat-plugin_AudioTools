# ============================================================
# Praat AudioTools - Spectral swirl effect.praat
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

form Spectral Swirl Effect
    comment This script applies sinusoidal frequency bin shifting
    comment WARNING: This process can have long runtime on long files
    comment due to FFT calculations
    comment Spectrum parameters:
    boolean fast_fourier no
    comment (Note: fast FFT not recommended for this effect)
    comment Swirl parameters:
    natural number_of_cycles 4
    comment (number of sinusoidal cycles across spectrum)
    positive maximum_bin_shift 100
    comment (maximum frequency bin displacement)
    comment Output options:
    positive scale_peak 0.99
    boolean play_after_processing 1
    boolean show_info_report 1
endform

# Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# Get the input sound
sound$ = selected$("Sound")
select Sound 'sound$'

# Convert to complex spectrum
origSpec = To Spectrum: fast_fourier
Rename: "origSpec"

# Make a copy to modify
swirlSpec = Copy: "swirlSpec"

# Apply the spectral swirl effect
# Sinusoidally shift frequency bins with clamping
Formula: "if row = 1 then if round(col + 'maximum_bin_shift' * sin(2 * pi * 'number_of_cycles' * col / ncol)) < 1 then Spectrum_origSpec[1,1] else if round(col + 'maximum_bin_shift' * sin(2 * pi * 'number_of_cycles' * col / ncol)) > ncol then Spectrum_origSpec[1,ncol] else Spectrum_origSpec[1, round(col + 'maximum_bin_shift' * sin(2 * pi * 'number_of_cycles' * col / ncol))] fi fi else if round(col + 'maximum_bin_shift' * sin(2 * pi * 'number_of_cycles' * col / ncol)) < 1 then Spectrum_origSpec[2,1] else if round(col + 'maximum_bin_shift' * sin(2 * pi * 'number_of_cycles' * col / ncol)) > ncol then Spectrum_origSpec[2,ncol] else Spectrum_origSpec[2, round(col + 'maximum_bin_shift' * sin(2 * pi * 'number_of_cycles' * col / ncol))] fi fi fi"

# Convert back to sound
swirled_sound = To Sound
Rename: "'sound$'_spectral_swirl"

# Scale to peak
Scale peak: scale_peak

# Clean up intermediate spectra
selectObject: origSpec, swirlSpec
Remove

# Select result
selectObject: swirled_sound

# Show info report if requested
if show_info_report
    clearinfo
    appendInfoLine: "Spectral swirl processing complete!"
    appendInfoLine: "Original: ", sound$
    appendInfoLine: "Created: ", sound$, "_spectral_swirl"
    appendInfoLine: "Cycles: ", string$(number_of_cycles)
    appendInfoLine: "Depth: ", string$(maximum_bin_shift)
endif

# Play if requested
if play_after_processing
    Play
endif
