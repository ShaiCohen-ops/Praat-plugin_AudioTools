# ============================================================
# Praat AudioTools - Harmonic_Comb.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Reverberation or diffusion script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Harmonic Comb Filter
    comment This script applies harmonic series-based comb filtering
    natural number_of_harmonics 7
    positive fundamental_delay_min 20
    positive fundamental_delay_max 100
    positive modulation_divisor 1000
    positive scale_peak 0.99
    boolean play_after_processing 1
endform

if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

originalName$ = selected$("Sound")
Copy: originalName$ + "_harmonic_comb"

a = Get number of samples
fundamental_delay = randomUniform(fundamental_delay_min, fundamental_delay_max)

for harmonic from 1 to number_of_harmonics
    harmonic_delay = fundamental_delay / harmonic
    harmonic_weight = 1.0 / (harmonic * harmonic)
    phase_shift = randomUniform(0, 2*pi)
    Formula: "self + 'harmonic_weight' * (self[col+'harmonic_delay'] - self[col]) * cos('phase_shift' + 2*pi*col*'harmonic'/'modulation_divisor')"
endfor

Scale peak: scale_peak

if play_after_processing
    Play
endif