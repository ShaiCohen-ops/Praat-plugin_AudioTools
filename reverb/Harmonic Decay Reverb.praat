# ============================================================
# Praat AudioTools - Harmonic Decay Reverb.praat
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

form Harmonic Decay Reverb
    comment This script creates delays based on harmonic intervals
    natural number_of_echoes 48
    positive base_delay_seconds 0.05
    positive decay_factor 0.92
    positive harmonic_spread 1.2
    positive amplitude_mean 0.25
    positive amplitude_stddev 0.08
    boolean play_after_processing 1
endform

if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

originalName$ = selected$("Sound")
Copy: originalName$ + "_harmonic_reverb"

for k from 1 to number_of_echoes
    harmonic_power = 1 / harmonic_spread
    harmonic_delay = base_delay_seconds * k^harmonic_power
    amplitude = decay_factor^k * randomGauss(amplitude_mean, amplitude_stddev)
    Formula: "self + amplitude * self(x - harmonic_delay)"
endfor

if play_after_processing
    Play
endif